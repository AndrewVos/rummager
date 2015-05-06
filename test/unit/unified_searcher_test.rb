require "test_helper"
require "set"
require "unified_searcher"
require "search_parameter_parser"

class UnifiedSearcherTest < ShouldaUnitTestCase
  def setup
    Timecop.freeze
    super
  end

  def sample_docs
    [{
      "_index" => "government-2014-03-19t14:35:28z-a05cfc73-933a-41c7-adc0-309a715baf09",
      _type: "edition",
      _id: "/government/publications/staffordshire-cheese",
      _score: 3.0514863,
      "fields" => {
        "description" => "Staffordshire Cheese Product of Designated Origin (PDO) and Staffordshire Organic Cheese.",
        "title" => "Staffordshire Cheese",
        "link" => "/government/publications/staffordshire-cheese",
      },
    }, {
      "_index" => "mainstream-2014-03-19t14:35:28z-6472f975-dc38-49a5-98eb-c498e619650c",
      _type: "edition",
      _id: "/duty-relief-for-imports-and-exports",
      _score: 0.49672604,
      "fields" => {
        "description" => "Schemes that offer reduced or zero rate duty and VAT for imports and exports",
        "title" => "Duty relief for imports and exports",
        "link" => "/duty-relief-for-imports-and-exports",
      },
    }, {
      "_index" => "detailed-2014-03-19t14:35:27z-27e2831f-bd14-47d8-9c7a-3017e213efe3",
      _type: "edition",
      _id: "/dairy-farming-and-schemes",
      _score: 0.34655035,
      "fields" => {
        "description" => "Information on hygiene standards and milking practices for UK dairy farmers, with a guide to EU schemes for dairy farmers and producers",
        "title" => "Dairy farming and schemes",
        "link" => "/dairy-farming-and-schemes",
      },
    }]
  end

  def cma_case_allowed_values
    return {
      "case_state" => [
        {
          "label" => "Open",
          "value" => "open",
        },
        {
          "label" => "Closed",
          "value" => "closed",
        },
      ]
    }
  end

  def stub_suggester
    stub('Suggester', suggestions: ['cheese'])
  end

  def text_filter(field_name, values, reject = false)
    SearchParameterParser::TextFieldFilter.new(field_name, values, reject)
  end

  def date_filter(field_name, values, reject = false)
    SearchParameterParser::DateFieldFilter.new(field_name, values, reject)
  end

  BASE_CHEESE_QUERY = {
    function_score: {
      boost_mode: :multiply,
      query: {
        function_score: {
          boost_mode: :multiply,
          query: {bool: {
            should: [
              {bool: {
                must: [
                  {match: {_all: {
                    query: 'cheese',
                    analyzer: 'query_default',
                    minimum_should_match: '2<2 3<3 7<50%'
                  }}},
                ],
                should: [
                  {match_phrase: {'title' => {query: 'cheese', analyzer: 'query_default'}}},
                  {match_phrase: {'acronym' => {query: 'cheese', analyzer: 'query_default'}}},
                  {match_phrase: {'description' => {query: 'cheese', analyzer: 'query_default'}}},
                  {match_phrase: {'indexable_content' => {query: 'cheese', analyzer: 'query_default'}}},
                  {multi_match: {
                    query: 'cheese',
                    operator: 'and',
                    fields: ['title', 'acronym', 'description', 'indexable_content'],
                    analyzer: 'query_default',
                  }},
                  {multi_match: {
                    query: 'cheese',
                    operator: 'or',
                    fields: ['title', 'acronym', 'description', 'indexable_content'],
                    analyzer: 'shingled_query_analyzer',
                  }},
                ]}
              },
            ]
          }},
          functions: [
            {filter: {term: {format: 'smart-answer'}}, boost_factor: 1.5},
            {filter: {term: {format: 'transaction'}}, boost_factor: 1.5},
            {filter: {term: {format: 'topical_event'}}, boost_factor: 1.5},
            {filter: {term: {format: 'minister'}}, boost_factor: 1.7},
            {filter: {term: {format: 'organisation'}}, boost_factor: 2.5},
            {filter: {term: {format: 'topic'}}, boost_factor: 1.5},
            {filter: {term: {format: 'document_series'}}, boost_factor: 1.3},
            {filter: {term: {format: 'document_collection'}}, boost_factor: 1.3},
            {filter: {term: {format: 'operational_field'}}, boost_factor: 1.5},
            {filter: {term: {format: 'contact'}}, boost_factor: 0.3},
            {filter: {term: {search_format_types: 'announcement'}}, script_score: {
              script: "((0.05 / ((3.16*pow(10,-11)) * abs(now - doc['public_timestamp'].date.getMillis()) + 0.05)) + 0.12)",
              params: {now: (Time.now.to_i / 60) * 60000},
            }},
            {filter: {term: {organisation_state: 'closed'}}, boost_factor: 0.3},
            {filter: {term: {organisation_state: 'devolved'}}, boost_factor: 0.3},
            {filter: {term: {is_historic: true}}, boost_factor: 0.5},
          ],
          score_mode: 'multiply',
        }
      },
      script_score: {
        script: "doc['popularity'].value + #{UnifiedSearchBuilder::POPULARITY_OFFSET}"
      },
    }
  }

  CHEESE_QUERY = {
    indices: {
      index: :government,
      query: {
        function_score: {
          query: BASE_CHEESE_QUERY,
          boost_factor: 0.4
        }
      },
      no_match_query: {
        indices: {
          index: :"service-manual",
          query: {
            function_score: {
              query: BASE_CHEESE_QUERY,
              boost_factor: 0.1
            }
          },
          no_match_query: BASE_CHEESE_QUERY
        }
      }
    }
  }

  # Set BASE_FILTERS if needed to add some default filters to search.
  BASE_FILTERS = nil

  def mock_best_bets(query)
    @metasearch_index = stub("metasearch index")
    @metasearch_index.stubs(:raw_search).with(
      {
        query: {:bool => {:should => [{:match => {:exact_query => query}},
                                      {:match => {:stemmed_query => query}}]}},
        size: 1000,
        fields: [:details, :stemmed_query_as_term],
      }, "best_bet").returns(
      {
        "hits" => {"hits" => [], "total" => [].size}
      })
    @metasearch_index.stubs(:analyzed_best_bet_query).with(query).returns(query)
  end

  def with_base_filters(filter)
    if BASE_FILTERS
      {
        "and" => [
          filter,
          BASE_FILTERS
        ]
      }
    else
      filter
    end
  end

  def make_searcher
    UnifiedSearcher.new(@combined_index, @metasearch_index, {}, stub_suggester)
  end

  def make_schema
    schema = stub("schema")
    index_schema = stub("index schema")

    schema.stubs(:schema_for_alias_name).returns(index_schema)
    schema.stubs(:field_definitions)
    index_schema.stubs(:document_type).returns(sample_document_types["cma_case"])
    schema
  end

  context "unfiltered, unsorted search" do

    setup do
      @combined_index = stub("unified index")
      mock_best_bets("cheese")
      @searcher = make_searcher
      @combined_index.expects(:raw_search).with({
        from: 0,
        size: 20,
        query: CHEESE_QUERY,
        fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
      }).returns({
        "hits" => {"hits" => sample_docs, "total" => 3}
      })
      @combined_index.stubs(:index_names).returns(
        %w{mainstream detailed government}
      )
      @combined_index.stubs(:schema).returns(make_schema)

      @results = @searcher.search({
        start: 0,
        count: 20,
        query: "cheese",
        order: nil,
        filters: {},
        return_fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
        debug: {},
      })
    end

    should "include results from all indexes" do
      assert_equal(
        ["government", "mainstream", "detailed"].to_set,
        @results[:results].map { |result|
          result[:index]
        }.to_set
      )
    end

    should "include total result count" do
      assert_equal(3, @results[:total])
    end

    should "include suggested queries" do
      assert_equal ['cheese'], @results[:suggested_queries]
    end
  end

  context "unfiltered, sorted search" do

    setup do
      @combined_index = stub("unified index")
      mock_best_bets("cheese")
      @searcher = make_searcher
      @combined_index.stubs(:raw_search).with({
        from: 0,
        size: 20,
        query: CHEESE_QUERY,
        fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
        sort: [{"public_timestamp" => {order: "asc", missing: "_last"}}],
      }).returns({
        "hits" => {"hits" => sample_docs, "total" => 3}
      })
      @combined_index.stubs(:index_names).returns(
        %w{mainstream detailed government}
      )
      @combined_index.stubs(:schema).returns(make_schema)

      @results = @searcher.search({
        start: 0,
        count: 20,
        query: "cheese",
        order: ["public_timestamp", "asc"],
        filters: {},
        return_fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
        debug: {},
      })
    end

    should "include results from all indexes" do
      assert_equal(
        ["government", "mainstream", "detailed"].to_set,
        @results[:results].map do |result|
          result[:index]
        end.to_set
      )
    end

    should "include total result count" do
      assert_equal(3, @results[:total])
    end
  end

  context "filtered, unsorted search" do

    setup do
      @combined_index = stub("unified index")
      mock_best_bets("cheese")
      @searcher = make_searcher
      @combined_index.stubs(:raw_search).with({
        from: 0,
        size: 20,
        query: CHEESE_QUERY,
        filter: with_base_filters({"terms" => {"organisations" => ["ministry-of-magic"]}}),
        fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
      }).returns({
        "hits" => {"hits" => sample_docs, "total" => 3}
      })
      @combined_index.stubs(:index_names).returns(
        %w{mainstream detailed government}
      )
      @combined_index.stubs(:schema).returns(make_schema)

      @results = @searcher.search({
        start: 0,
        count: 20,
        query: "cheese",
        filters: [ text_filter("organisations", ["ministry-of-magic"]) ],
        return_fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
        facets: nil,
        debug: {},
      })
    end

    should "include results from all indexes" do
      assert_equal(
        ["government", "mainstream", "detailed"].to_set,
        @results[:results].map do |result|
          result[:index]
        end.to_set
      )
    end

    should "include total result count" do
      assert_equal(3, @results[:total])
    end
  end

  context "faceted, unsorted search" do

    setup do
      @combined_index = stub("unified index")
      mock_best_bets("cheese")
      @searcher = make_searcher
      @combined_index.stubs(:raw_search).with({
        from: 0,
        size: 20,
        query: CHEESE_QUERY,
        facets: {
          "organisations" => {
            terms: {
              field: "organisations",
              order: "count",
              size: 100000,
            },
          }
        },
        fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
      }).returns({
        "hits" => {"hits" => sample_docs, "total" => 3},
        "facets" => {"organisations" => {
          "missing" => 7,
          "terms" => [
            {"term" => "a", "count" => 2,},
            {"term" => "b", "count" => 1,},
          ]
        }},
      })
      @combined_index.stubs(:index_names).returns(
        %w{mainstream detailed government}
      )
      @combined_index.stubs(:schema).returns(make_schema)

      @results = @searcher.search({
        start: 0,
        count: 20,
        query: "cheese",
        filters: {},
        return_fields: SearchParameterParser::ALLOWED_RETURN_FIELDS,
        facets: {"organisations" => {requested: 1, examples: 0, example_fields: [], order: SearchParameterParser::DEFAULT_FACET_SORT, scope: :exclude_field_filter}},
        debug: {},
      })
    end

    should "include results from all indexes" do
      assert_equal(
        ["government", "mainstream", "detailed"].to_set,
        @results[:results].map do |result|
          result[:index]
        end.to_set
      )
    end

    should "include total result count" do
      assert_equal(3, @results[:total])
    end

    should "include requested number of facet options" do
      facet = @results[:facets]["organisations"]
      assert_equal(1, facet[:options].length)
    end

    should "have correct top facet option" do
      facet = @results[:facets]["organisations"]
      assert_equal({value: {"slug" => "a"}, documents: 2}, facet[:options][0])
    end

    should "include requested number of facets" do
      facet = @results[:facets]["organisations"]
      assert_equal(2, facet[:total_options])
      assert_equal(1, facet[:missing_options])
    end

    should "include number of documents with no value" do
      facet = @results[:facets]["organisations"]
      assert_equal(7, facet[:documents_with_no_value])
    end

    should "include requested facet scope" do
      facet = @results[:facets]["organisations"]
      assert_equal(:exclude_field_filter, facet[:scope])
    end
  end

end
