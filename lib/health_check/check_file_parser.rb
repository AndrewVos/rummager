require "csv"
require "health_check/search_check"

module HealthCheck
  class CheckFileParser
    def initialize(file)
      @file = file
    end

    def checks
      checks = []
      logger << "\nStatus,Path,Search Term,Position,Expectation,Message,Row\n"

      CSV.parse(@file, headers: true).each do |row|
        begin
          check = SearchCheck.new
          check.search_term      = row["When I search for..."]
          check.imperative       = row["Then I..."]
          check.path             = row["see..."].sub(%r{https://www.gov.uk}, "")
          check.minimum_rank     = Integer(row["in the top ... results"])
          check.weight = parse_integer_with_comma(row["Monthly searches"]) || 1

          if check.valid?
            checks << check
          else
            logger << "ERROR,,,,Invalid or incomplete row,#{row.to_s.chomp.gsub(",", "")}\n"
          end
        rescue => e
          logger << "ERROR,,,,Invalid or incomplete row - #{e.message},#{row.to_s.chomp.gsub(",", "")}\n"
        end
      end
      checks
    end

    private
      def parse_integer_with_comma(raw)
        if raw.nil? || raw.strip.empty?
          nil
        else
          Integer(raw.gsub(",", ""))
        end
      end

      def logger
        Logging.logger[self]
      end
  end
end
