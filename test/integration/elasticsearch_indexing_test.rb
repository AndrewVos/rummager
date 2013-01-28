require "integration_test_helper"
require "app"
require "rest-client"

class ElasticsearchIndexingTest < IntegrationTest

  def setup
    use_elasticsearch_for_primary_search
    disable_secondary_search
    WebMock.disable_net_connect!(allow: "localhost:9200")
  end

  def test_should_send_a_document_to_elasticsearch_when_a_json_document_is_posted
    reset_elasticsearch_index

    test_data = {
      "title" => "TITLE",
      "description" => "DESCRIPTION",
      "format" => "answer",
      "link" => "/an-example-answer",
      "indexable_content" => "HERE IS SOME CONTENT"
    }

    post "/documents", JSON.dump(test_data)
    get "/documents/%2Fan-example-answer"

    parsed_response = JSON.parse(last_response.body)

    test_data.each do |key, value|
      assert_equal value, parsed_response[key]
    end

    assert_equal test_data.keys.sort, parsed_response.keys.sort
  end

  def test_should_be_able_to_index_a_document_with_additional_fields
    add_field_to_mappings("topics")
    reset_elasticsearch_index

    test_data = {
      "title" => "TITLE",
      "description" => "DESCRIPTION",
      "format" => "answer",
      "link" => "/an-example-answer",
      "indexable_content" => "HERE IS SOME CONTENT",
      "topics" => [1,2]
    }

    post "/documents", JSON.dump(test_data)
    get "/documents/%2Fan-example-answer"

    parsed_response = JSON.parse(last_response.body)

    test_data.each do |key, value|
      assert_equal value, parsed_response[key]
    end

    assert_equal test_data.keys.sort, parsed_response.keys.sort
  end
end
