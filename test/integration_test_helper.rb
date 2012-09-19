require "test_helper"
require 'slimmer/test'
require "app"

require "htmlentities"

module ResponseAssertions
  def assert_response_text(needle)
    haystack = HTMLEntities.new.decode(last_response.body.gsub(/<[^>]+>/, " ").gsub(/\s+/, " "))
    message = "Expected to find #{needle.inspect} in\n#{haystack}"
    assert haystack.include?(needle), message
  end
end

module IntegrationFixtures
  def sample_document_attributes
    {
      "title" => "TITLE1",
      "description" => "DESCRIPTION",
      "format" => "local_transaction",
      "humanized_format" => "Services",
      "presentation_format" => "local_transaction",
      "section" => "life-in-the-uk",
      "link" => "/URL"
    }
  end

  def sample_document
    Document.from_hash(sample_document_attributes)
  end

  def sample_recommended_document_attributes
    {
      "title" => "TITLE1",
      "description" => "DESCRIPTION",
      "format" => "recommended-link",
      "link" => "/URL"
    }
  end

  def sample_recommended_document
    Document.from_hash(sample_recommended_document_attributes)
  end

  def sample_section
    Section.new("bob")
  end
end

class IntegrationTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include ResponseAssertions
  include IntegrationFixtures

  def app
    Sinatra::Application
  end

  def disable_secondary_search
    @secondary_search.stubs(:search).returns([])
  end

  def use_solr_for_primary_search
    settings.stubs(:primary_search).returns(
      {
        type: "solr",
        server: "solr-test-server",
        port: 9999,
        path: "/solr/rummager"
      }
    )
  end

  def use_elasticsearch_for_primary_search
    settings.stubs(:primary_search).returns(
      {
        type: "elasticsearch",
        server: "localhost",
        port: 9200,
        index_name: "rummager_test"
      }
    )
  end

  def delete_elasticsearch_index
    begin
      RestClient.delete "http://localhost:9200/rummager_test"
    rescue RestClient::Exception => exception
      raise unless exception.http_code == 404
    end
  end

  # NOTE: This will not create any mappings
  # TODO: come back and make mappings
  def reset_elasticsearch_index
    delete_elasticsearch_index
    RestClient.put "http://localhost:9200/rummager_test", ""

    schema = YAML.load_file(File.expand_path("../../elasticsearch_schema.yml", __FILE__))
    schema["mapping"].each do |mapping_type, mapping|
      RestClient.put(
        "http://localhost:9200/rummager_test/#{mapping_type}/_mapping",
        {mapping_type => mapping}.to_json
      )
    end

  end

  def stub_primary_and_secondary_searches
    @primary_search = stub_everything("Mainstream Solr wrapper")
    Backends.any_instance.stubs(:primary_search).returns(@primary_search)

    @secondary_search = stub_everything("Whitehall Solr wrapper")
    Backends.any_instance.stubs(:secondary_search).returns(@secondary_search)
  end
end
