require "test_helper"
require "multi_json"
require "elasticsearch/search_server"
require "elasticsearch/index_group"

class IndexGroupTest < MiniTest::Unit::TestCase

  def setup
    @server = Elasticsearch::SearchServer.new(
      "http://localhost:9200/",
      {
        "index" => {
          "settings" => "awesomeness"
        },
        "mappings" => {
          "default" => {
            "edition" => { "_all" => { "enabled" => true } }
          }
        }
      }
    )
  end

  def test_create_index
    expected_body = MultiJson.encode({
      "settings" => "awesomeness",
      "mappings" => {
        "edition" => { "_all" => { "enabled" => true } }
      }
    })
    stub = stub_request(:put, %r(http://localhost:9200/mainstream-.*/))
      .with(body: expected_body)
      .to_return(
        status: 200,
        body: '{"ok": true, "acknowledged": true}'
      )
    @server.index_group("mainstream").create_index

    assert_requested(stub)
  end
end
