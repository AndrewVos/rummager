require "test_helper"
require "elasticsearch/base_worker"
require "elasticsearch/delete_worker"
require "elasticsearch/index"

class DeleteWorkerTest < MiniTest::Unit::TestCase
  def test_deletes_documents
    mock_index = mock("index")
    mock_index.expects(:delete).with("edition", "/foobang")
    CustomElasticsearch::SearchServer.any_instance.expects(:index)
      .with("test-index")
      .returns(mock_index)

    worker = CustomElasticsearch::DeleteWorker.new
    worker.perform("test-index", "edition", "/foobang")
  end

  def test_retries_when_index_locked
    lock_delay = CustomElasticsearch::DeleteWorker::LOCK_DELAY
    mock_index = mock("index")
    mock_index.expects(:delete).raises(CustomElasticsearch::IndexLocked)
    CustomElasticsearch::SearchServer.any_instance.expects(:index)
      .with("test-index")
      .returns(mock_index)

    CustomElasticsearch::DeleteWorker.expects(:perform_in)
      .with(lock_delay, "test-index", "edition", "/foobang")

    worker = CustomElasticsearch::DeleteWorker.new
    worker.perform("test-index", "edition", "/foobang")
  end

  def test_forwards_to_failure_queue
    stub_message = {}
    Airbrake.expects(:notify_or_ignore).with(CustomElasticsearch::BaseWorker::FailedJobException.new(stub_message))
    fail_block = CustomElasticsearch::DeleteWorker.sidekiq_retries_exhausted_block
    fail_block.call(stub_message)
  end
end
