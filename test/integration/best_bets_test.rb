require "integration_test_helper"

class BestBetsTest < IntegrationTest
  def setup
    stub_elasticsearch_settings
    reset_content_indexes
    create_meta_indexes
  end

  def teardown
    clean_test_indexes
  end

  def test_exact_best_bet
    commit_document("mainstream_test",
      link: '/an-organic-result',
      indexable_content: 'I will turn up in searches for "a forced best bet"',
    )

    commit_document("mainstream_test",
    link: '/the-link-that-should-surface',
      indexable_content: 'Empty.',
    )

    add_best_bet(
      query: 'a forced best bet',
      type: 'exact',
      link: '/the-link-that-should-surface',
      position: 1,
    )

    links = get_links "/unified_search?q=a+forced+best+bet"

    assert_equal ["/the-link-that-should-surface", "/an-organic-result"], links
  end

  def test_exact_worst_bet
    commit_document("mainstream_test",
      indexable_content: 'I should not be shown.',
      link: '/we-never-show-this',
    )

    add_worst_bet(
      query: 'shown',
      type: 'exact',
      link: '/we-never-show-this',
      position: 1,
    )

    links = get_links "/unified_search?q=shown"

    refute links.include?("/we-never-show-this")
  end

  def test_stemmed_best_bet
    commit_document("mainstream_test",
      link: '/the-link-that-should-surface',
    )

    add_best_bet(
      query: 'best bet',
      type: 'stemmed',
      link: '/the-link-that-should-surface',
      position: 1,
    )

    links = get_links "/unified_search?q=best+bet+and+such"

    assert_equal ["/the-link-that-should-surface"], links
  end

  def test_stemmed_best_bet_variant
    commit_document("mainstream_test",
      link: '/the-link-that-should-surface',
    )

    add_best_bet(
      query: 'best bet',
      type: 'stemmed',
      link: '/the-link-that-should-surface',
      position: 1,
    )

    # note that we're searching for "bests bet", not "best bet" here.
    links = get_links "/unified_search?q=bests+bet"

    assert_equal ["/the-link-that-should-surface"], links
  end

  def test_stemmed_best_bet_words_not_in_phrase_order
    commit_document("mainstream_test",
      link: '/only-shown-for-exact-matches',
    )

    add_best_bet(
      query: 'best bet',
      type: 'stemmed',
      link: '/only-shown-for-exact-matches',
      position: 1,
    )

    # note that we're searching for "bet best", not "best bet" here.
    links = get_links "/unified_search?q=bet+best"

    refute links.include?("/only-shown-for-exact-matches")
  end

private

  def get_links(path)
    get(path)
    parsed_response["results"].map { |result| result["link"] }
  end

  def add_best_bet(args)
    payload = build_sample_bet_hash(
      query: args[:query],
      type: args[:type],
      best_bets: [args.slice(:link, :position)],
      worst_bets: [],
    )

    post "/metasearch_test/documents", payload.to_json
    commit_index("metasearch_test")
  end

  def add_worst_bet(args)
    payload = build_sample_bet_hash(
      query: args[:query],
      type: args[:type],
      best_bets: [],
      worst_bets: [args.slice(:link, :position)],
    )

    post "/metasearch_test/documents", payload.to_json
    commit_index("metasearch_test")
  end

  def build_sample_bet_hash(query:, type:, best_bets:, worst_bets:)
    {
      "#{type}_query" => query,
      details: JSON.generate(
        {
          best_bets: best_bets,
          worst_bets: worst_bets,
        }
      ),
      _type: "best_bet",
      _id: "#{query}-#{type}",
    }
  end
end
