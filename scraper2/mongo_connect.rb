require "uri"
require "net/http"
require 'httparty'
require 'json'
require 'rufus-scheduler'
require 'open-uri'
require 'nokogiri'

# bin/phantomjs --webdriver=9999
# jobs -p | xargs kill -9

require 'selenium-webdriver'

hash = {}
work_queue = []

def start
  response = HTTParty.get('http://ghostify.herokuapp.com/links/untouched')
  if response.code == 200
    body = response.body
    work_queue = JSON.parse(body)

    puts "Queue: #{work_queue.count}"
    if work_queue.count > 0
      if execute_scraping(work_queue)
        work_queue = []
      end
    end
  end
end


def execute_scraping (array)
  count = 0
  while (count < array.length)
    full_link = array[count]["full_link"]

    puts "Scraping (#{ (count + 1) }/#{array.count}) #{full_link}"
    result = execute_scraper2(full_link)
    count = count + 1
    send_post(result)

  end
  return true
end

def execute_scraper2(full_link)
  hash = {}
  hash["transcript"] = get_captions(full_link)
  if hash["transcript"]
    hash["details"] = getDetails(full_link)
  end
  return hash
end

def getDetails(full_link)
  hash = {}
  page = Nokogiri::HTML(open(full_link))
  hash["views"] = page.css(".watch-view-count").inner_html.gsub!(',','').to_i
  hash["thumbnail"] = page.css("link[itemprop=thumbnailUrl]").first.attributes["href"].value
  hash["title"] = page.css("#eow-title").inner_html
  hash["link"] = full_link

  return hash
end

def get_captions(full_link)
  # supply video ID or full YouTube URL from command line
  arg = full_link

  if arg =~ /^#{URI::regexp}$/
    link = arg
  else
    link = "http://www.youtube.com/watch?v=#{arg}"
  end

  puts "Link: (#{link})"

  # PhantomJS server
  driver = Selenium::WebDriver.for(:remote, :url => "http://localhost:9999")
  wait = Selenium::WebDriver::Wait.new(:timeout => 10) # seconds

  driver.navigate.to link

  overflow_button = driver.find_element(:id, 'action-panel-overflow-button')
  overflow_button.click

  transcript_button = driver.find_element(:class, 'action-panel-trigger-transcript')
  transcript_button.click

  # wait for at least one transcript line
  wait.until { driver.find_element(:id => 'cp-1') }

  transcript_container = driver.find_element(:id, 'transcript-scrollbox')

  cc = Nokogiri::HTML(transcript_container.attribute('innerHTML'))



  total = ""

  cc.css('.caption-line').each do |line|
  	transcript_line = line.css('.caption-line-time').text.gsub("\n", " ") + " " + line.css('.caption-line-text').text.gsub("\n", " ") + " "
  	total += transcript_line
  end

  driver.quit

  return total

end

def send_post(hash)
  uri = URI('http://ghostify.herokuapp.com/api/videos/create')
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP::Post.new(uri.path, initheader = {'Content-Type' =>'application/json'})
  req.body = hash.to_json
  puts req.body
  res = http.request(req)
  puts "response #{res.body}"
end

scheduler = Rufus::Scheduler.new
scheduler.every '10s' do
  # do something in 10 days
  puts "Scheduler"
  if work_queue.count == 0
    puts "Starting..."
    start()
  end
end
scheduler.join
