require "yaml"
require "elasticsearch/search_server"

class SearchConfig

  def search_server
    puts "index_names: #{index_names}"
    puts "content_index_names: #{content_index_names}"
    Elasticsearch::SearchServer.new(
      elasticsearch["base_uri"],
      elasticsearch_schema,
      index_names,
      content_index_names,
    )
  end

  def index_names
    content_index_names + auxiliary_index_names
  end

  def content_index_names
    elasticsearch["content_index_names"] || []
  end

  def auxiliary_index_names
    elasticsearch["auxiliary_index_names"] || []
  end

  def elasticsearch_schema
    @elasticsearch_schema ||= config_for("elasticsearch_schema")
  end

  def elasticsearch
    @elasticsearch ||= config_for("elasticsearch")
  end

  def document_series_registry_index
    elasticsearch["document_series_registry_index"]
  end

  def document_collection_registry_index
    elasticsearch["document_collection_registry_index"]
  end

  def organisation_registry_index
    elasticsearch["organisation_registry_index"]
  end

  def topic_registry_index
    elasticsearch["topic_registry_index"]
  end

  def world_location_registry_index
    elasticsearch["world_location_registry_index"]
  end

  def govuk_index_names
    elasticsearch["govuk_index_names"]
  end

private
  def config_for(kind)
    YAML.load_file(File.expand_path("../#{kind}.yml", File.dirname(__FILE__)))
  end
end
