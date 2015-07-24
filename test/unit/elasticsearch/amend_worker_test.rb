require "test_helper"
require "elasticsearch/amend_worker"
require "elasticsearch/base_worker"
require "elasticsearch/index"

class AmendWorkerTest < MiniTest::Unit::TestCase
  def test_amends_documents
    mock_index = mock("index")
    mock_index.expects(:amend).with("/foobang", "title" => "New title")
    CustomElasticsearch::SearchServer.any_instance.expects(:index)
      .with("test-index")
      .returns(mock_index)

    worker = CustomElasticsearch::AmendWorker.new
    worker.perform("test-index", "/foobang", "title" => "New title")
  end

  def test_retries_when_index_locked
    lock_delay = CustomElasticsearch::DeleteWorker::LOCK_DELAY
    mock_index = mock("index")
    mock_index.expects(:amend).raises(CustomElasticsearch::IndexLocked)
    CustomElasticsearch::SearchServer.any_instance.expects(:index)
      .with("test-index")
      .returns(mock_index)

    CustomElasticsearch::AmendWorker.expects(:perform_in)
      .with(lock_delay, "test-index", "/foobang", "title" => "New title")

    worker = CustomElasticsearch::AmendWorker.new
    worker.perform("test-index", "/foobang", "title" => "New title")
  end

  def test_forwards_to_failure_queue
    stub_message = {}
    Airbrake.expects(:notify_or_ignore).with(CustomElasticsearch::BaseWorker::FailedJobException.new(stub_message))
    fail_block = CustomElasticsearch::AmendWorker.sidekiq_retries_exhausted_block
    fail_block.call(stub_message)
  end
end
