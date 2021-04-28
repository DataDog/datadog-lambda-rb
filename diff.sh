logs=$(
            cat loglog.log |
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
                perl -p -e "s/${!run_id}/XXXX/g" |
                # Normalize line numbers in stack traces
                perl -p -e 's/(.js:)[0-9]*:[0-9]*/\1XXX:XXX/g' |
                # Remove metrics and metas in logged traces (their order is inconsistent)
                perl -p -e 's/"(meta|metrics)":{(.*?)}/"\1":{"XXXX": "XXXX"}/g' |
                # Normalize enhanced metric datadog_lambda tag
                perl -p -e "s/(datadog_lambda:v)[0-9\.]+/\1X.X.X/g"
        )
echo $logs