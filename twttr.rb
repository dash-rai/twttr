require 'net/http'              # also requires open-uri
require 'json'
require 'open-uri'
require 'base64'
require 'nokogiri'
require 'fileutils'
require './config'

module Twttr
  
  class Request
    
    include Configuration       # from config.rb
    
    def initialize
      @@access_token ||= get_token()
    end
    
    def get_token
      #####
      # Format for app-only authentication can be found here
      # https://dev.twitter.com/docs/auth/application-only-auth
      #####
      
      token_resource = URI('https://api.twitter.com/oauth2/token')
      token_credential = Base64.strict_encode64(API_Twitter_key + ':' +
                                                API_Twitter_secret)

      Net::HTTP.start(token_resource.host, token_resource.port,
                      :use_ssl => token_resource.scheme == 'https') do |http|
        request = Net::HTTP::Post.new token_resource
        request['Authorization'] = "Basic #{token_credential}"
        request.body = "grant_type=client_credentials"
        request = add_headers(request)
        
        response = http.request(request)
        message = JSON.parse(response.body)
        if message["access_token"]
          return message["access_token"]
        elsif message["errors"]
          raise "Could not get Access Token. Twitter says: "\
          "#{message['errors'][0]['message']}"
        else
          raise "Could not get Access Token."
        end
      end      
    end

    def invalidate_token
      invalidate_resource = URI('https://api.twitter.com/oauth2/invalidate_token')
      token_credential = Base64.strict_encode64(API_Twitter_key + ':' + API_Twitter_secret)

      message = Net::HTTP.start(invalidate_resource.host, invalidate_resource.port,
                      :use_ssl => invalidate_resource.scheme == 'https') do |http|
        request = Net::HTTP::Post.new invalidate_resource
        request['Authorization'] = "Basic #{token_credential}"
        request['Accept'] = '*/*'
        request.body = "access_token=#{@@access_token}"
        request = add_headers(request)
        
        response = http.request(request)
        JSON.parse(response.body)
      end
      if message["access_token"]
        return message["access_token"]
      elsif message["errors"]
        raise "Could not get Access Token. Twitter says: "\
        "#{message['errors'][0]['message']}"
      else
        raise "Could not get Access Token."
      end
    end
    
    #sends a GET request to the specified Twitter API resource with parameters
    def send_get_request(resource, params)
      api_resource = 'https://api.twitter.com/1.1'
      uri = URI(api_resource + resource)              
      uri.query = URI.encode_www_form(params) # add parameters to resource
      #send HTTPS GET request
      response = Net::HTTP.start(uri.hostname, uri.port,
                                 :use_ssl => uri.scheme == 'https') do |http|
        req = Net::HTTP::Get.new uri
        req = add_headers(req)
        req['Authorization'] = "Bearer #{@@access_token}"
        res = http.request req
        JSON.parse(res.body) 
      end
      
      if response.empty? || response.nil?
        raise EmptyResponse
      end
      
      response
    end

    def add_headers(request)
      request['User-Agent'] = "My app"
      request['Content-Type'] = "application/x-www-form-urlencoded;charset=UTF-8"
      request
    end
    
    def write_url_to_binary_file(uri, path_to_write='.')
      Net::HTTP.start(uri.hostname, uri.port,
                      :use_ssl => uri.scheme == 'https') do |http|
        resp = http.get uri
        #create path if it doesn't exist
        dirname = File.dirname(path_to_write)
        unless File.directory?(dirname)
          FileUtils.mkdir_p(dirname)
        end
        open(path_to_write + uri.path.split('/').last, 'wb+') do |file|
          file.write(resp.body)
        end
      end
    end
  end

  # gets trends for a WOEID location
  def Twttr.trending(woeid=1)
    # Worldwide WOEID: 1
    req = Request.new
    response = req.send_get_request('/trends/place.json', {id: woeid})
    if response["errors"]
      raise "Could not find trends for that WOEID"
    else
      response
    end
  end

  # gets all of the user's tweets and retweets
  def Twttr.user_timeline(screen_name, options={count: 20})
    params = {include_rts: true}
    params[:screen_name] = screen_name
    params.merge!(options)
    
    req = Request.new
    
    begin
      response = req.send_get_request("/statuses/user_timeline.json", params)
    rescue EmptyResponse => e
      raise e, "Can't find any Tweets"
    end
    
    return response
  end

  # extract the media of at most 200 tweets at a time
  # and download them to a specified path
  def Twttr.download_tweets_media_parallel(*args, path_to_write)
    response = Twttr.user_timeline(*args)
    threads = response.map do |tweet|
      Thread.new(tweet['entities']['media']) do |media|
        if media
          media.each do |media_to_fetch|
            uri = URI(media_to_fetch['media_url'])
            Request::write_url_to_binary_file(uri, path_to_write)
          end
        end
      end
    end
    threads.each { |thr| thr.join }
    return response.last['id']
  end

  def Twttr.puts_tweets(*args)
    response = Twttr.user_timeline(*args)
    response.each do |tweet|
      puts tweet["text"]
      puts "posted at #{tweet['created_at']}"
      puts
    end

    return response.last['id']
  end

  def Twttr.closest_woeid(lat, long)
    req = Request.new
    req.send_get_request('/trends/closest.json',
                         {lat: lat, long: long})
  end
  
  def Twttr.get_lat_long(location)
    uri = ("http://where.yahooapis.com/v1/places.q('#{location}')"\
           "?appid=#{API_Yahoo_ID}")
    xml = Nokogiri::XML(open(uri))
    element = xml.xpath("/*/*/*[11]/*")
    return element[0].child.text, element[1].child.text
  end
end
