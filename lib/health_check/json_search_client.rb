require "uri"
require "net/http"
require "json"
require "cgi"

module HealthCheck
  class JsonSearchClient

    RESPONSE_INDEX_KEYS = {
      "mainstream" => "services-information",
      "detailed" => "services-information",
      "government" => "departments-policy"
    }

    def initialize(options={})
      @base_url       = options[:base_url] || URI.parse("https://www.gov.uk/api/search.json")
      @authentication = options[:authentication] || nil
      @index          = options[:index] || "mainstream"
    end

    def search(term)
      request = Net::HTTP::Get.new((@base_url + "?q=#{CGI.escape(term)}").request_uri)
      request.basic_auth(*@authentication) if @authentication
      response = http_client.request(request)
      case response
        when Net::HTTPSuccess # 2xx
          json_response = JSON.parse(response.body)
          resp = extract_results(json_response)
        else
          raise "Unexpected response #{response}"
      end
    end

    def to_s
      "JSON endpoint #{@base_url} [index=#{@index} auth=#{@authentication ? "yes" : "no"}]"
    end

    private
      def http_client
        @_http_client ||= begin
          http = Net::HTTP.new(@base_url.host, @base_url.port)
          http.use_ssl = (@base_url.scheme == "https")
          http
        end
      end

      def extract_results(json_response)
        if json_response.is_a?(Hash) && json_response.has_key?('streams') # combined search endpoint
          extract_combined_results(json_response['streams'])
        elsif json_response.is_a?(Hash) && json_response.has_key?('results') # unified search endpoint
          json_response['results'].map { |result| result["link"] }
        else
          raise "Unexpected response format: #{json_response.inspect}"
        end
      end

      def extract_combined_results(streams)
        index_key = RESPONSE_INDEX_KEYS[@index]
        selected_stream = streams[index_key]

        # Count top results as being effectively present in all tabs
        [streams['top-results'], selected_stream].map {|stream|
          stream['results'].map {|result|
            result['link']
          }
        }.flatten
      end
  end
end
