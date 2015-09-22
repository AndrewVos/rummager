class DocumentPreparer
  def initialize(client, content_api)
    @client = client
    @content_api = content_api
  end

  def prepared(doc_hash, popularities, options, is_content_index)
    if is_content_index
      doc_hash = prepare_popularity_field(doc_hash, popularities)
      doc_hash = prepare_tags(doc_hash)
      doc_hash = prepare_format_field(doc_hash)
    end

    doc_hash = prepare_if_best_bet(doc_hash)
    doc_hash
  end

private

  def prepare_popularity_field(doc_hash, popularities)
    pop = 0.0
    unless popularities.nil?
      link = doc_hash["link"]
      pop = popularities[link]
    end
    doc_hash.merge("popularity" => pop)
  end

  def artefact_for_link(link)
    if link.match(/\Ahttps?:\/\//)
      # We don't support tags for things which are external links.
      return nil
    end
    link = link.sub(/\A\//, '')
    begin
      @content_api.artefact!(link)
    rescue GdsApi::HTTPNotFound
      nil
    end
  end

  def tags_from_artefact(artefact)
    tags = Hash.new { [] }
    artefact.tags.each do |tag|
      slug = tag.slug
      type = tag.details.type
      case type
      when "organisation"
        tags["organisations"] <<= slug
      when "section"
        tags["mainstream_browse_pages"] <<= slug
      when "specialist_sector"
        tags["specialist_sectors"] <<= slug
      end
    end
    tags
  end

  def merge_tags(doc_hash, extra_tags)
    merged_tags = {}
    %w{specialist_sectors mainstream_browse_pages organisations}.each do |tag_type|
      merged_tags[tag_type] = doc_hash.fetch(tag_type, []).concat(extra_tags[tag_type]).uniq
    end
    merged_tags
  end

  def prepare_tags(doc_hash)
    artefact = artefact_for_link(doc_hash["link"])
    if artefact.nil?
      return doc_hash
    end
    from_content_api = tags_from_artefact(artefact)

    doc_hash.merge(merge_tags(doc_hash, from_content_api))
  end

  def prepare_format_field(doc_hash)
    if doc_hash["format"].nil?
      doc_hash.merge("format" => doc_hash["_type"])
    else
      doc_hash
    end
  end

  # If a document is a best bet, and is using the stemmed_query field, we
  # need to populate the stemmed_query_as_term field with a processed version
  # of the field.  This produces a representation of the best-bet query with
  # all words stemmed and lowercased, and joined with a single space.
  #
  # At search time, all best bets with at least one word in common with the
  # user's query are fetched, and the stemmed_query_as_term field of each is
  # checked to see if it is a substring match for the (similarly normalised)
  # user's query.  If so, the best bet is used.
  def prepare_if_best_bet(doc_hash)
    if doc_hash["_type"] != "best_bet"
      return doc_hash
    end

    stemmed_query = doc_hash["stemmed_query"]
    if stemmed_query.nil?
      return doc_hash
    end

    doc_hash["stemmed_query_as_term"] = " #{analyzed_best_bet_query(stemmed_query)} "
    doc_hash
  end

  # duplicated in index.rb
  def analyzed_best_bet_query(query)
    analyzed_query = JSON.parse(@client.get_with_payload(
      "_analyze?analyzer=best_bet_stemmed_match", query))

    analyzed_query["tokens"].map { |token_info|
      token_info["token"]
    }.join(" ")
  end
end
