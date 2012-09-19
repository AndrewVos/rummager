require "integration_test_helper"
require "app"
require "rest-client"

class ElasticsearchSearchTest < IntegrationTest

  def setup
    use_elasticsearch_for_primary_search
    disable_secondary_search
    WebMock.disable_net_connect!(allow: "localhost:9200")
    reset_elasticsearch_index
    add_sample_documents
    refresh_index
  end

  def sample_document_attributes
    [
      {
        "title" => "Cheese in my face",
        "description" => "Hummus weevils",
        "format" => "answer",
        "link" => "/an-example-answer",
        "indexable_content" => "I like my badger: he is tasty and delicious"
      },
      {
        "title" => "Useful government information",
        "description" => "Government, government, government. Developers.",
        "format" => "answer",
        "link" => "/another-example-answer",
        "indexable_content" => "Tax, benefits, roads and stuff"
      }
    ]
  end

  def add_sample_documents
    sample_document_attributes.each do |sample_document|
      post "/documents", JSON.dump(sample_document)
      assert last_response.ok?
    end
  end

  def refresh_index
    # TODO: replace this with a Rummager request when we have support
    RestClient.post "http://localhost:9200/rummager_test/_refresh", ""
  end

  def test_should_search_by_content
    get "/search.json?q=badger"
    assert last_response.ok?
    parsed_response = JSON.parse(last_response.body)
    assert_equal ["/an-example-answer"], parsed_response.map { |r| r["link"] }
  end

  def test_should_match_stems
    get "/search.json?q=badgers"
    assert last_response.ok?
    parsed_response = JSON.parse(last_response.body)
    assert_equal ["/an-example-answer"], parsed_response.map { |r| r["link"] }
  end

  def test_should_search_by_title
    get "/search.json?q=cheese"
    assert last_response.ok?
    parsed_response = JSON.parse(last_response.body)
    assert_equal ["/an-example-answer"], parsed_response.map { |r| r["link"] }
  end

  def test_should_search_by_description
    get "/search.json?q=hummus"
    assert last_response.ok?
    parsed_response = JSON.parse(last_response.body)
    assert_equal ["/an-example-answer"], parsed_response.map { |r| r["link"] }
  end
end
