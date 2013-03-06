require "test_helper"
require "elasticsearch/index"
require "webmock"

class ElasticsearchIndexTest < MiniTest::Unit::TestCase
  include Fixtures::DefaultMappings

  def setup
    base_uri = URI.parse("http://example.com:9200")
    @wrapper = Elasticsearch::Index.new(base_uri, "test-index", default_mappings)
  end

  def test_real_name
    stub_request(:get, "http://example.com:9200/test-index/_aliases")
      .to_return(
        body: MultiJson.encode({"real-name" => { "aliases" => { "test-index" => {} } }}),
        headers: {"Content-Type" => "application/json"}
      )

    assert_equal "real-name", @wrapper.real_name
  end

  def test_real_name_when_no_index
    # elasticsearch is weird: even though /index/_status 404s if the index
    # doesn't exist, /index/_aliases returns a 200.
    stub_request(:get, "http://example.com:9200/test-index/_aliases")
      .to_return(
        status: 200,
        body: "{}",
        headers: {"Content-Type" => "application/json"}
      )

    assert_nil @wrapper.real_name
  end

  def test_should_bulk_update_documents
    # TODO: factor out with FactoryGirl
    json_document = {
        "_type" => "edition",
        "link" => "/foo/bar",
        "title" => "TITLE ONE",
    }
    document = stub("document", elasticsearch_export: json_document)
    # Note that this comes with a trailing newline, which elasticsearch needs
    payload = <<-eos
{"index":{"_type":"edition","_id":"/foo/bar"}}
{"_type":"edition","link":"/foo/bar","title":"TITLE ONE"}
    eos
    stub_request(:post, "http://example.com:9200/test-index/_bulk").with(
        body: payload,
        headers: {"Content-Type" => "application/json"}
    )
    @wrapper.add [document]
    assert_requested(:post, "http://example.com:9200/test-index/_bulk")
  end

  def test_get_document
    document_url = "http://example.com:9200/test-index/_all/%2Fan-example-link"
    document_hash = {
      "_type" => "edition",
      "link" => "/an-example-link",
      "title" => "I am a title"
    }

    document_response = {
      "_index" => "test-index",
      "_type" => "edition",
      "_id" => "/an-example-link",
      "_version" => 4,
      "exists" => true,
      "_source" =>  document_hash
    }
    stub_request(:get, document_url).to_return(body: document_response.to_json)

    document = @wrapper.get("/an-example-link")
    assert document.is_a? Document
    assert_equal "/an-example-link", document.get(:link)
    assert_equal "/an-example-link", document.link
    assert_equal document_hash["title"], document.title
    assert_requested :get, document_url
  end

  def test_get_document_not_found
    document_url = "http://example.com:9200/test-index/_all/%2Fa-bad-link"

    not_found_response = {
      "_index" => "rummager",
      "_type" => "edition",
      "_id" => "/a-bad-link",
      "exists" => false
    }.to_json

    stub_request(:get, document_url).to_return(
      status: 404,
      body: not_found_response
    )

    assert_nil @wrapper.get("/a-bad-link")
    assert_requested :get, document_url
  end

  def test_basic_keyword_search
    stub_request(:get, "http://example.com:9200/test-index/_search").with(
      body: %r{"query":"keyword search"},
      headers: {"Content-Type" => "application/json"}
    ).to_return(:body => '{"hits":{"hits":[]}}')
    @wrapper.search "keyword search"
    assert_requested(:get, "http://example.com:9200/test-index/_search")
  end

  def test_commit
    refresh_url = "http://example.com:9200/test-index/_refresh"
    stub_request(:post, refresh_url).to_return(
      body: '{"ok":true,"_shards":{"total":1,"successful":1,"failed":0}}'
    )
    @wrapper.commit
    assert_requested :post, refresh_url
  end
end
