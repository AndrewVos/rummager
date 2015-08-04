class DataMassager
  attr_accessor :data

  def initialize()
    @data = []
  end

  def add(args = {})
    data << massage(args)
  end

  def headings
    [
      "Status",
      "Path",
      "Search Term",
      "Position",
      "Expectation",
      "Error Message",
      "Error Row",
    ]
  end

private
  def massage(data)
    massaged_data = {}
    headings.each do |heading|
      if data.has_key?(heading)
        massaged_data[heading] = data[heading]
      else
        massaged_data[heading] = ""
      end
    end
    massaged_data
  end
end
