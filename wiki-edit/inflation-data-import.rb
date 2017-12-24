#!/usr/bin/env ruby

# A little script to import inflation data from csv to wikidata checking if those years have values
# from IMF as first

require "mediawiki_api"
require 'csv'
require 'rubygems'
require 'faraday'
require 'json'

require_relative ".env/config" #USERNAME & PWD set here

WIKI_API_URL = "https://www.wikidata.org/w/api.php"
DATA_RELATIVE_LOC = File.join(File.dirname(__FILE__), "./data/imf-dm-export-20171219.csv")
LOG_RELATIVE_LOC = File.join(File.dirname(__FILE__), "./logs/wiki_import-failed")
REFERENCE_URL = "http://www.imf.org/external/datamapper/PCPIEPCH@WEO?year="
SPARQL_ENDPOINT = 'https://query.wikidata.org/sparql'
PROPERTY_ID = "P1279"

main()

def main()
  client = MediawikiApi::Client.new WIKI_API_URL
  client.log_in USERNAME, PWD

  CSV.foreach(DATA_RELATIVE_LOC, quote_char: '"', col_sep: ',', row_sep: :auto, headers: true) do |row|
    begin 
      puts "Select which wikidata entity is #{row['Country']}"
      country_id = select_country_id(client, row['Country'])

      puts "POSTing SPARQL query to #{SPARQL_ENDPOINT}, to find years already had"
      uneeded_years = years_not_to_add(client, country_id)

      json_edit = "["
      (1980..2016).each do |year|
        if !(uneeded_years.include? year.to_s)
          if row[year.to_s] != "no data"
            json_edit += get_json_of_data_point(year, row[year.to_s]) + "\n,\n"
          end
        end
      end

      # if there is no data to add skip to next country
      next if json_edit.length == 1
      # clip uneeded comma for final and add closing array, surreound with claims array syntax
      json_edit = "{ \"claims\":" + json_edit.chomp(",\n") + "]}"

      response = client.action :wbeditentity, id: country_id, format: 'json', data: json_edit, http_method: :post

      if !(response.status == 200)
        raise "#{response.status} code response to edit request"
      end
    rescue => e
      File.open(filename, 'a') {|f| f.write("#{row['Country']}\n") }
      puts e.message
      puts "Press 'y' to continue"
      answer = gets.chomp
      return unless answer == 'y'
    end
  end
end

def select_country_id(client, country_name)
  response = client.action :wbsearchentities, search: country_name, language: 'en', http_method: :get

  # check response and response data type
  if !(response.status == 200)
    raise "#{response.status} code response to search"
  end
  search_results = response.data['search']
  if !(search_results.is_a? Array) || !(search_results.length > 0)
    raise "Zero length or non-array returned"
  end

  (0 .. (search_results.length - 1)).each do |index|
    puts "#{index}) #{search_results[index]['label']}\n   #{search_results[index]['description']}"
  end

  chosen_index = get_user_choice(search_results.length - 1)
  if !chosen_index then raise "User exit in selection" end

  return search_results[chosen_index]['id']
end

def years_not_to_add(client, country_id)
  ref_term   = "ref"
  date_term  = "date"
  value_term = "value"
  ref_regex  = /(http(s)?:\/\/www\.)?imf\.org.*/
  
  query = "SELECT ?#{value_term} ?#{date_term} ?#{ref_term}
  WHERE { 
    wd:#{country_id} wdt:P1279 ?#{value_term}.
    wd:#{country_id} p:P1279 ?property.
    ?property pq:P585 ?#{date_term}.
    ?property prov:wasDerivedFrom ?refnode.
    ?refnode pr:P854 ?#{ref_term}.
  }"
  
  response = Faraday.get SPARQL_ENDPOINT, {query: query, format: 'json'}
  if !(response.status == 200)
    raise "#{response.status} code response to inflation SPARQL"
  end
  inflation_data_points = JSON(response.body)['results']['bindings']
  if !(inflation_data_points.is_a? Array)
    raise "Non-array returned for inflation"
  end
  # get all years which have imf reference
  currently_held_inflation_years = inflation_data_points.map{ |dp| dp[date_term]['value'][0..3] if dp[ref_term]['value'] =~ ref_regex}.compact

  return currently_held_inflation_years
end

def get_json_of_data_point(year, data_point)
  return "
  {
    \"mainsnak\": {
        \"snaktype\": \"value\",
        \"property\": \"P1279\",
        \"datavalue\": {
            \"value\": {
                \"amount\": \"#{data_point}\",
                \"unit\": \"http://www.wikidata.org/entity/Q11229\"
            },
            \"type\": \"quantity\"
        },
        \"datatype\": \"quantity\"
    },
    \"type\": \"statement\",
    \"qualifiers\": {
        \"P585\": [
            {
                \"snaktype\": \"value\",
                \"property\": \"P585\",
                \"datavalue\": {
                    \"value\": {
                        \"time\": \"+#{year}-01-01T00:00:00Z\",
                        \"timezone\": 0,
                        \"before\": 0,
                        \"after\": 0,
                        \"precision\": 9,
                        \"calendarmodel\": \"http://www.wikidata.org/entity/Q1985727\"
                    },
                    \"type\": \"time\"
                },
                \"datatype\": \"time\"
            }
        ]
    },
    \"qualifiers-order\": [
        \"P585\"
    ],
    \"rank\": \"normal\",
    \"references\": [
        {
            \"snaks\": {
                \"P854\": [
                    {
                        \"snaktype\": \"value\",
                        \"property\": \"P854\",
                        \"datavalue\": {
                            \"value\": \"http://www.imf.org/external/datamapper/PCPIEPCH@WEO?year=#{year}\",
                            \"type\": \"string\"
                        },
                        \"datatype\": \"url\"
                    }
                ]
            },
            \"snaks-order\": [
                \"P854\"
            ]
        }
    ]
  }"
end

def get_logfile()
  version = 0
  filename = LOG_RELATIVE_LOC + version

  while !(File.file?(filename))
    version++
    filename =  LOG_RELATIVE_LOC + version
  end

  File.open(filename, 'w') {|f| f.write("") }
  return filename
end

def get_user_choice(max_index)
  begin
    puts "Select a number or q to skip:"
    choice = gets.chomp
    if choice == 'q'
      return nil
    end
    choice = Integer(choice)
  rescue
    retry
  end while !(0 <= choice && choice <= max_index) 

  return choice.to_i
end
