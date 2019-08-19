# frozen_string_literal: true

module DDLambda
  module Trace
    def self.convert_xray_to_apm_trace_id(xray_trace_id)
      parts = xray_trace_id.split('-')
      return nil if parts.length < 3

      last_part = parts[2]
      return nil if last_part.length != 24
      # Make sure every character is hex
      return nil if last_part.upcase[/\H/]

      hex = last_part.to_i(16)
      last_63_bits = hex & 0x7fffffffffffffff
      last_63_bits.to_s(10)
    end

    def self.convert_xray_parent_id_to_apm_parent_id(xray_parent_id)
      return nil if xray_parent_id.length != 16
      return nil if xray_parent_id.upcase[/\H/]

      hex = xray_parent_id.to_i(16)
      hex.to_s(10)
    end
  end
end

#
# export function convertToAPMParentID(xrayParentID: string): string | undefined {
#   if (xrayParentID.length !== 16) {
#     return;
#   }
#   const hex = new BigNumber(xrayParentID, 16);
#   if (hex.isNaN()) {
#     return;
#   }
#   return hex.toString(10);
# }
