require "test_helper"
require "elasticsearch/search_server"
require "search_config"

class SearchServerTest < MiniTest::Unit::TestCase
  EMPTY_SCHEMA = { "mappings" => { "default" => nil } }

  def test_returns_an_index
    search_server = Elasticsearch::SearchServer.new("http://l", EMPTY_SCHEMA, ["a", "b"], ["a"], SearchConfig.new)
    index = search_server.index("a")
    assert index.is_a?(Elasticsearch::Index)
    assert_equal "a", index.index_name
  end

  def test_raises_an_error_for_unknown_index
    search_server = Elasticsearch::SearchServer.new("http://l", EMPTY_SCHEMA, ["a", "b"], ["a"], SearchConfig.new)
    assert_raises Elasticsearch::NoSuchIndex do
      search_server.index("z")
    end
  end

  def test_can_get_multi_index
    search_server = Elasticsearch::SearchServer.new("http://l", EMPTY_SCHEMA, ["a", "b"], ["a"], SearchConfig.new)
    index = search_server.index("a,b")
    assert index.is_a?(Elasticsearch::Index)
    assert_equal "a,b", index.index_name
  end

  def test_raises_an_error_for_unknown_index_in_multi_index
    search_server = Elasticsearch::SearchServer.new("http://l", EMPTY_SCHEMA, ["a", "b"], ["a"], SearchConfig.new)
    assert_raises Elasticsearch::NoSuchIndex do
      search_server.index("a,z")
    end
  end

end
