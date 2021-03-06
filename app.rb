require "rest-client"
require "sinatra"
require "json"
require "csv"
require "redis"

%w[ lib ].each do |path|
  $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
end

require "document"
require "result_presenter"
require "unified_searcher"
require "elasticsearch/index"
require "elasticsearch/search_server"
require "matcher_set"
require "parameter_parser/search_parameter_parser"
require "parameter_parser/facet_parameter_parser"
require "search_parameters"
require "registries"
require "schema/combined_index_schema"

require_relative "config"
require_relative "helpers"

require "routes/content"

class Rummager < Sinatra::Application
  def search_server
    settings.search_config.search_server
  end

  def current_index
    index_name = params["index"] || settings.default_index_name
    search_server.index(index_name)
  rescue Elasticsearch::NoSuchIndex
    halt(404)
  end

  def registries
    @@registries ||= Registries.new(
      search_server,
      settings.search_config
    )
  end

  def unified_index_schema
    @unified_index_schema ||= CombinedIndexSchema.new(
      settings.search_config.content_index_names,
      settings.search_config.schema_config
    )
  end

  def unified_index
    search_server.index_for_search(settings.search_config.content_index_names)
  end

  def text_error(content)
    halt 403, {"Content-Type" => "text/plain"}, content
  end

  def json_only
    unless [nil, "json"].include? params[:request_format]
      expires 86400, :public
      halt 404
    end
  end

  helpers do
    include Helpers
  end

  before do
    content_type :json
  end

  error RestClient::RequestTimeout do
    halt(503, "Elasticsearch timed out")
  end

  error Redis::TimeoutError do
    halt(503, "Redis queue timed out")
  end

  error Elasticsearch::InvalidQuery do
    halt(422, env['sinatra.error'].message)
  end

  error Elasticsearch::BulkIndexFailure do
    halt(500, env['sinatra.error'].message)
  end

  # Return results for the GOV.UK site search
  #
  # For details, see docs/unified-search-api.md
  get "/unified_search.?:request_format?" do
    json_only

    parser = SearchParameterParser.new(
      parse_query_string(request.query_string),
      unified_index_schema,
    )

    unless parser.valid?
      status 422
      return { error: parser.error }.to_json
    end

    search_params = SearchParameters.new(parser.parsed_params)
    searcher = UnifiedSearcher.new(unified_index, registries)
    searcher.search(search_params).to_json
  end

  # Perform an advanced search. Supports filters and pagination.
  #
  # Returns the first N results if no keywords or filters supplied
  #
  # Required parameters:
  #   per_page              - eg "40"
  #   page                  - eg "1"
  #
  # Optional parameters:
  #   order[fieldname]      - eg order[public_timestamp]=desc
  #   keywords              - eg "tax"
  #
  # Arbitrary "filter parameters", anything which is defined in the mappings
  # for the index is allowed. Examples:
  #   search_format_types[]        - eg "consultation"
  #   topics[]                     - eg "climate-change"
  #   organisations[]              - eg "cabinet-office"
  #   relevant_to_local_government - eg "1"
  #
  # If the field type is defined as "date", this is possible:
  #   fieldname[from]     - eg public_timestamp[from]="2013-04-30"
  #   fieldname[to]      - eg public_timestamp[to]="2013-04-30"
  #
  get "/:index/advanced_search.?:request_format?" do
    json_only

    # Using request.params because it is just the params from the request
    # rather than things added by Sinatra (eg splat, captures, index and format)
    result_set = current_index.advanced_search(request.params)
    results = result_set.results.map do |document|
      # Wrap in hash to be compatible with the way UnifiedSearch works.
      raw_result = { "fields" => document.to_hash }
      search_params = SearchParameters.new(return_fields: raw_result['fields'].keys)
      ResultPresenter.new(raw_result, {}, nil, search_params).present
    end

    { total: result_set.total, results: results }.to_json
  end

  # Insert (or overwrite) a document
  post "/?:index?/documents" do
    request.body.rewind
    documents = [JSON.parse(request.body.read)].flatten.map { |hash|
      current_index.document_from_hash(hash)
    }

    if settings.enable_queue
      current_index.add_queued(documents)
      json_result 202, "Queued"
    else
      simple_json_result(current_index.add(documents))
    end
  end

  post "/?:index?/commit" do
    simple_json_result(current_index.commit)
  end

  delete "/?:index?/documents/*" do
    document_link = params["splat"].first

    if (type = get_type_from_request_body(request.body))
      id = document_link
    else
      type, id = current_index.link_to_type_and_id(document_link)
    end

    if settings.enable_queue
      current_index.delete_queued(type, id)
      json_result 202, "Queued"
    else
      simple_json_result(current_index.delete(type, id))
    end
  end

  def get_type_from_request_body(request_body)
    JSON.parse(request_body.read).fetch("_type", nil)
  rescue JSON::ParserError
    nil
  end

  # Update an existing document
  post "/?:index?/documents/*" do
    unless request.form_data?
      halt(
        415,
        {"Content-Type" => "text/plain"},
        "Amendments require application/x-www-form-urlencoded data"
      )
    end

    begin
      if settings.enable_queue
        current_index.amend_queued(params["splat"].first, request.POST)
        json_result 202, "Queued"
      else
        current_index.amend(params["splat"].first, request.POST)
        json_result 200, "OK"
      end
    rescue ArgumentError => e
      text_error e.message
    rescue Elasticsearch::DocumentNotFound
      halt 404
    end
  end

  delete "/?:index?/documents" do

    if params["delete_all"]
      # No longer supported; instead use the
      # `rummager:switch_to_empty_index` Rake command
      halt 400
    else
      action = current_index.delete(params["link"])
    end
    simple_json_result(action)
  end

  get "/_status" do
    status = {}
    status["queues"] = {}

    retries = Sidekiq::RetrySet.new.group_by(&:queue)
    scheduled = Sidekiq::ScheduledSet.new.group_by(&:queue)

    Sidekiq::Stats.new.queues.each do |queue_name, queue_size|
      retry_count = retries.fetch(queue_name, []).size
      scheduled_count = scheduled.fetch(queue_name, []).size
      status["queues"][queue_name] = {
        "jobs" => queue_size,
        "retries" => retry_count,
        "scheduled" => scheduled_count
      }
    end
    status.to_json
  end

end
