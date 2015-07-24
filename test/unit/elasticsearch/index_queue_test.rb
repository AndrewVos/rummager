require "test_helper"
require "elasticsearch/index_queue"
require "elasticsearch/bulk_index_worker"
require "elasticsearch/delete_worker"

class IndexQueueTest < MiniTest::Unit::TestCase
  def sample_document_hashes
    %w(foo bar baz).map do |slug|
      {:link => "/#{slug}", :title => slug.capitalize}
    end
  end

  def test_can_queue_documents_in_bulk
    CustomElasticsearch::BulkIndexWorker.expects(:perform_async)
      .with("test-index", sample_document_hashes)
    queue = CustomElasticsearch::IndexQueue.new("test-index")
    queue.queue_many(sample_document_hashes)
  end

  def test_can_delete_documents
    CustomElasticsearch::DeleteWorker.expects(:perform_async)
      .with("test-index", "edition", "/foobang")
    queue = CustomElasticsearch::IndexQueue.new("test-index")
    queue.queue_delete("edition", "/foobang")
  end

  def test_can_amend_documents
    CustomElasticsearch::AmendWorker.expects(:perform_async)
      .with("test-index", "/foobang", "title" => "Cheese")
    queue = CustomElasticsearch::IndexQueue.new("test-index")
    queue.queue_amend("/foobang", "title" => "Cheese")
  end
end
