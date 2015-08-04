require_relative "../../test_helper"
require "health_check/data_massager"
require 'pry'
module HealthCheck
  class DataMassagerTest < ShouldaUnitTestCase
    context "adding data" do

      should "have no data when instantiated" do
        massager = DataMassager.new
        assert_equal 0, massager.data.count
      end

      should "add data" do

        data = {
          "Status" => "some value",
        }
        massager = DataMassager.new
        massager.add(data)

        assert_equal 1, massager.data.count

      end

      should "handle missing data" do

        data = {
          "Status" => "some value",
        }
        massager = DataMassager.new
        massager.add(data)

        assert_equal [{
          "Status" => "some value",
          "Path" => "",
          "Search Term" => "",
          "Position" => "",
          "Expectation" => "",
          "Error Message" => "",
          "Error Row" => "",
        }], massager.data

      end
    end
  end
end
