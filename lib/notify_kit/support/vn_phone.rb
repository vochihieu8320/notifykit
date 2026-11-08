# frozen_string_literal: true

module NotifyKit
  module Support
    # Vietnamese mobile numbers in the format Zalo ZNS (and most VN SMS gateways)
    # expect: country code, no plus, no leading zero => "84912345678".
    #
    #   VnPhone.normalize("0912 345 678")  # => "84912345678"
    #   VnPhone.normalize("+84 912-345-678") # => "84912345678"
    module VnPhone
      # Mobile prefixes after the country code: 3x, 5x, 7x, 8x, 9x + 8 digits.
      MOBILE = /\A84[35789]\d{8}\z/

      module_function

      # @return [String, nil] normalized number, or nil when it is not a VN mobile
      def normalize(raw)
        digits = raw.to_s.gsub(/[\s.\-()]/, "")
        digits = digits.delete_prefix("+")
        digits = "84#{digits[1..]}" if digits.start_with?("0")
        digits.match?(MOBILE) ? digits : nil
      end

      def normalize!(raw)
        normalize(raw) || raise(InvalidRecipient, "not a Vietnamese mobile number: #{mask(raw)}")
      end

      # Keep phone numbers out of logs/errors: "0912345678" => "091****678"
      def mask(raw)
        s = raw.to_s
        s.length > 6 ? "#{s[0, 3]}#{'*' * (s.length - 6)}#{s[-3..]}" : "***"
      end
    end
  end
end
