require "integration_test_helper"
require "cgi"

class ElasticsearchIndexingTest < IntegrationTest

  def setup
    stub_elasticsearch_settings
    try_remove_test_index
    @sample_document = {
      "title" => "TITLE",
      "description" => "DESCRIPTION",
      "format" => "answer",
      "link" => "/an-example-answer",
      "indexable_content" => "HERE IS SOME CONTENT"
    }
  end

  def teardown
    clean_test_indexes
  end

  def test_should_indicate_success_in_response_code_when_adding_a_new_document
    create_test_indexes

    insert_document("mainstream_test", @sample_document)
    assert last_response.ok?
  end

  def test_after_adding_a_document_to_index_should_be_able_to_retrieve_it_again
    create_test_indexes

    insert_document("mainstream_test", @sample_document)

    assert_document_is_in_rummager(@sample_document)
  end

  def test_can_index_fields_of_type_opaque_object
    create_test_indexes

    document = {
      "format" => "statistics_announcemnt",
      "link" => "/a-link",
      "metadata" => {
        "confirmed" => true,
        "display_date" => "27 August 2014 9:30am",
      },
    }

    insert_document("mainstream_test", document)

    assert_document_is_in_rummager(document)
  end
end
