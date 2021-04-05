#!/bin/bash

# Usage - run commands from repo root:
# To check if new changes to the layer cause changes to any snapshots:
#   BUILD_LAYERS=true DD_API_KEY=XXXX aws-vault exec sandbox-account-admin -- ./scripts/run_integration_tests
# To regenerate snapshots:
#   UPDATE_SNAPSHOTS=true DD_API_KEY=XXXX aws-vault exec sandbox-account-admin -- ./scripts/run_integration_tests

set -e

# These values need to be in sync with serverless.yml, where there needs to be a function
# defined for every handler_runtime combination
LAMBDA_HANDLERS=("async-metrics" "sync-metrics" "http-requests" "http-error" "process-input-traced")
RUNTIMES=("ruby25" "ruby27")

LOGS_WAIT_SECONDS=20

script_path=${BASH_SOURCE[0]}
scripts_dir=$(dirname $script_path)
repo_dir=$(dirname $scripts_dir)
integration_tests_dir="$repo_dir/integration_tests"

script_utc_start_time=$(date -u +"%Y%m%dT%H%M%S")

mismatch_found=false

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "No AWS credentials were found in the environment."
    echo "Note that only Datadog employees can run these integration tests."
    exit 1
fi

if [ -z "$DD_API_KEY" ]; then
    echo "No DD_API_KEY env var set, exiting"
    exit 1
fi

if [ -n "$UPDATE_SNAPSHOTS" ]; then
    echo "Overwriting snapshots in this execution"
fi

if [ -n "$BUILD_LAYERS" ]; then
    echo "Building layers that will be deployed with our test functions"
    source $scripts_dir/build_layers.sh
else
    echo "Not building layers, ensure they've already been built or re-run with 'BUILD_LAYERS=true DD_API_KEY=XXXX ./scripts/run_integration_tests.sh'"
fi

cd $integration_tests_dir
input_event_files=$(ls ./input_events)
# Sort event files by name so that snapshots stay consistent
input_event_files=($(for file_name in ${input_event_files[@]}; do echo $file_name; done | sort))

# Generate a random 8-character ID to avoid collisions with other runs
run_id=$(xxd -l 4 -c 4 -p < /dev/random)

# Always remove the stack before exiting, no matter what
function remove_stack() {
    echo "Removing functions"
    serverless remove --stage $run_id
}
trap remove_stack EXIT

echo "Deploying functions"
serverless deploy --stage $run_id

echo "Invoking functions"
set +e # Don't exit this script if an invocation fails or there's a diff
for input_event_file in "${input_event_files[@]}"; do
    for handler_name in "${LAMBDA_HANDLERS[@]}"; do
        for runtime in "${RUNTIMES[@]}"; do
            function_name="${handler_name}_${runtime}"
            # Get event name without trailing ".json" so we can build the snapshot file name
            input_event_name=$(echo "$input_event_file" | sed "s/.json//")
            # Return value snapshot file format is snapshots/return_values/{handler}_{runtime}_{input-event}
            snapshot_path="./snapshots/return_values/${function_name}_${input_event_name}.json"

            return_value=$(serverless invoke --stage $run_id -f $function_name --path "./input_events/$input_event_file")

            if [ ! -f $snapshot_path ]; then
                # If the snapshot file doesn't exist yet, we create it
                echo "Writing return value to $snapshot_path because no snapshot exists yet"
                echo "$return_value" >$snapshot_path
            elif [ -n "$UPDATE_SNAPSHOTS" ]; then
                # If $UPDATE_SNAPSHOTS is set to true, write the new logs over the current snapshot
                echo "Overwriting return value snapshot for $snapshot_path"
                echo "$return_value" >$snapshot_path
            else
                # Compare new return value to snapshot
                diff_output=$(echo "$return_value" | diff - $snapshot_path)
                if [ $? -eq 1 ]; then
                    echo "Failed: Return value for $function_name does not match snapshot:"
                    echo "$diff_output"
                    mismatch_found=true
                else
                    echo "Ok: Return value for $function_name with $input_event_name event matches snapshot"
                fi
            fi
        done
    done
done
set -e

echo "Sleeping $LOGS_WAIT_SECONDS seconds to wait for logs to appear in CloudWatch..."
sleep $LOGS_WAIT_SECONDS

set +e # Don't exit this script if there is a diff or the logs endpoint fails
echo "Fetching logs for invocations and comparing to snapshots"
for handler_name in "${LAMBDA_HANDLERS[@]}"; do
    for runtime in "${RUNTIMES[@]}"; do
        function_name="${handler_name}_${runtime}"
        function_snapshot_path="./snapshots/logs/$function_name.log"

        # Fetch logs with serverless cli, retrying to avoid AWS account-wide rate limit error
        retry_counter=0
        while [ $retry_counter -lt 10 ]; do
            raw_logs=$(serverless logs --stage $run_id -f $function_name --startTime $script_utc_start_time)
            fetch_logs_exit_code=$?
            if [ $fetch_logs_exit_code -eq 1 ]; then
                echo "Retrying fetch logs for $function_name..."
                retry_counter=$(($retry_counter + 1))
                sleep 10
                continue
            fi
            break
        done

        if [ $retry_counter -eq 9 ]; then
            echo "FAILURE: Could not retrieve logs for $function_name"
            echo "Error from final attempt to retrieve logs:"
            echo $raw_logs

            exit 1
        fi

        # Replace invocation-specific data like timestamps and IDs with XXXX to normalize logs across executions
        logs=$(
            echo "$raw_logs" |
                # Filter serverless cli errors
                sed '/Serverless: Recoverable error occurred/d' |
                # Normalize Lambda runtime report logs
                perl -p -e 's/(RequestId|TraceId|SegmentId|Duration|Memory Used|"e"):( )?[a-z0-9\.\-]+/\1:\2XXXX/g' |
                # Normalize DD APM headers and AWS account ID
                perl -p -e "s/(x-datadog-parent-id:|x-datadog-trace-id:|account_id:)[0-9]+/\1XXXX/g" |
                # Strip API key from logged requests
                perl -p -e "s/(api_key=|'api_key': ')[a-z0-9\.\-]+/\1XXXX/g" |
                # Normalize log timestamps
                perl -p -e "s/[0-9]{4}\-[0-9]{2}\-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+( \(\-?\+?[0-9:]+\))?/XXXX-XX-XX XX:XX:XX.XXX/" |
                # Normalize DD trace ID injection
                perl -p -e "s/(dd\.trace_id=)[0-9]+ (dd\.span_id=)[0-9]+/\1XXXX \2XXXX/" |
                # Normalize execution ID in logs prefix
                perl -p -e $'s/[0-9a-z]+\-[0-9a-z]+\-[0-9a-z]+\-[0-9a-z]+\-[0-9a-z]+\t/XXXX-XXXX-XXXX-XXXX-XXXX\t/' |
                # Normalize minor package version tag so that these snapshots aren't broken on version bumps
                perl -p -e "s/(dd_lambda_layer:[0-9]+\.)[0-9]+\.[0-9]+/\1XX\.X/g" |
                perl -p -e "s/(dd_trace:[0-9]+\.)[0-9]+\.[0-9]+/\1XX\.X/g" |
                # Normalize data in logged traces
                perl -p -e 's/"(span_id|parent_id|trace_id|start|duration|tcp\.local\.address|tcp\.local\.port|dns\.address|request_id|function_arn|allocations|system.pid)":("?)[a-zA-Z0-9\.:\-]+("?)/"\1":\2XXXX\3/g' |
                # Strip out run ID (from function name, resource, etc.)
                perl -p -e "s/$run_id/XXXX/g" |
                # Normalize line numbers in stack traces
                perl -p -e 's/(.js:)[0-9]*:[0-9]*/\1XXX:XXX/g' |
                # Remove metrics and metas in logged traces (their order is inconsistent)
                perl -p -e 's/"(meta|metrics)":{(.*?)}/"\1":{"XXXX": "XXXX"}/g' |
                # Normalize enhanced metric datadog_lambda tag
                perl -p -e "s/(datadog_lambda:v)[0-9\.]+/\1X.X.X/g"
        )

        if [ ! -f $function_snapshot_path ]; then
            # If no snapshot file exists yet, we create one
            echo "Writing logs to $function_snapshot_path because no snapshot exists yet"
            echo "$logs" >$function_snapshot_path
        elif [ -n "$UPDATE_SNAPSHOTS" ]; then
            # If $UPDATE_SNAPSHOTS is set to true write the new logs over the current snapshot
            echo "Overwriting log snapshot for $function_snapshot_path"
            echo "$logs" >$function_snapshot_path
        else
            # Compare new logs to snapshots
            diff_output=$(echo "$logs" | diff - $function_snapshot_path)
            if [ $? -eq 1 ]; then
                echo "Failed: Mismatch found between new $function_name logs (first) and snapshot (second):"
                echo "$diff_output"
                mismatch_found=true
            else
                echo "Ok: New logs for $function_name match snapshot"
            fi
        fi
    done
done
set -e

if [ "$mismatch_found" = true ]; then
    echo "FAILURE: A mismatch between new data and a snapshot was found and printed above."
    echo "If the change is expected, generate new snapshots by running 'UPDATE_SNAPSHOTS=true DD_API_KEY=XXXX ./scripts/run_integration_tests.sh'"
    echo "Make sure https://httpstat.us/400/ is UP for the `http_error` test case"
    exit 1
fi

if [ -n "$UPDATE_SNAPSHOTS" ]; then
    echo "SUCCESS: Wrote new snapshots for all functions"
    exit 0
fi

echo "SUCCESS: No difference found between snapshots and new return values or logs"
