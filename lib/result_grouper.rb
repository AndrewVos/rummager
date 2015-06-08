class ResultGrouper

  MAXIMUM_NUMBER_OF_GROUPS = 3


  def initialize(results, allowed_group_fields, field_presenter)
    @results = results
    @allowed_group_fields = allowed_group_fields
    @field_presenter = field_presenter
  end

  def group
      groups = @results
      groups = group_by(allowed_group_fields)

      # three times - try and find the best group in the results, remove the
      # results in that group, try again
      @allowed_group_fields.
      unless @allowed_group_fields.include? "specialist_sectors"
        groups = group_by("specialist_sectors")
      else
        groups = []
      end

      top_groups = groups.sort_by { |_, info|
        -info[1]
      }.slice(0, 3).select { |_, info|
        info[0] > 2 && info[0] > 0.25
      }.map { |topic, info|
        topic_details = @field_presenter.expand("specialist_sectors", topic)
        {
          title: topic_details["title"] || topic_details,
          examples: info[2],
          link: topic_details["link"],
          format: "group",
          grouped_by: [ "specialist_sectors", topic_details["slug"] ],
          _metadata: {
            "_index" => "mainstream",
            "_type" => "group",
          }
        }
      }

      exclude_links = top_groups.map { |group| group[:link] }

      if top_groups
        links_in_groups = {}
        result_by_link = {}
        @results.each { |result|
          result_by_link[result["link"]] = result
        }
        top_groups.each_with_index { |group, index|
          group[:examples].each { |example|
            links_in_groups[example] = links_in_groups.fetch(example, [])
            links_in_groups[example] << index
          }
        }
        grouped_results = []
        @results.each { |result|
          if result["format"] == "specialist_sector"
            if exclude_links.include? result["link"]
              next
            end
          end
          result_groups = links_in_groups[result["link"]]
          if result_groups && result_groups.count > 0
            result_group = result_groups.first
            group = top_groups[result_group]
            top_groups[result_group] = nil
            if group
              if group[:examples].count > 5
                group[:suggested_filter] = {
                  count: 10,
                  name: "#{group[:title]}",
                  field: group[:grouped_by][0],
                  value: [group[:grouped_by][1]],
                }
              end
              group[:examples] = group[:examples].slice(0, 5).map { |example|
                result_by_link[example]
              }
              grouped_results << group
            end
          else
            grouped_results << result
#            result[:suggested_filter] = {
#              count: 10,
#              name: "VAT",
#              field: 'f',
#              value: ['f'],
#            }
          end
        }
        grouped_results
      else
        @results
      end
  end

private

  def filtered_on?(field)
    !(@applied_filters.find { |filter| filter.field_name == field }.nil?)
  end


  def group_by(fields)
    groups = {}
    @results.slice(0, 50).each_with_index do |doc, index|
      topics = [doc[field]].flatten
      if topics
        topics.compact.each do |topic|
          group = groups.fetch(topic, [0, 0.0, []])
          groups[topic] = [
            group[0] + 1,
            group[1] + 1.0 / (index + 3),
            group[2] + [doc["link"]]
          ]
        end
      end
    end
    groups
  end
end
