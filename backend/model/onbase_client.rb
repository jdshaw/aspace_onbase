require 'net/http'
require 'net/http/post/multipart'


class OnbaseClient

  def initialize(opts = {})
    @base_url = AppConfig[:onbase_robi_url]
    @username = AppConfig[:onbase_robi_username]
    @password = AppConfig[:onbase_robi_password]

    @user = opts.fetch(:user)
  end


  def maybe_parse_json(response)
    begin
      ASUtils.json_parse(response.body)
    rescue JSON::ParserError
      Log.error("Couldn't parse response as JSON: #{response.inspect} -- #{response.body}")
      raise ReferenceError.new("Unrecognized response from Onbase web service")
    end
  end


  def upload(file_stream, file_name, content_type, doc_type, keywords = {})
    upload_url = url('', {"documentTypeName" => doc_type})
    req = Net::HTTP::Post::Multipart.new(upload_url.request_uri,
                                         "file" => UploadIO.new(file_stream, content_type, file_name),
                                         "keywordData" => {"keywords" => format_keywords(keywords)}.to_json)

    req.basic_auth @username, @password

    res = http_request(upload_url) do |http|
      http.request(req)
    end

    if res.code =~ /^2/
      ASUtils.json_parse(res.body)
    else
      error = maybe_parse_json(res)
      Log.error(error)
      raise ReferenceError.new(error["message"])
    end
  end


  def get(suffix, headers = {})
    get_url = url(suffix)

    http_request(get_url) do |http|
      req = Net::HTTP::Get.new(get_url.request_uri)

      headers.each {|k,v| req[k] = v }

      req.basic_auth @username, @password
      response = http.request(req)

      if response.code != "200"
        raise "Failure in GET request from onbase: #{response.body}"
      end

      response
    end
  end


  def get_json(suffix)
    res = get(suffix, {"Accept" => "text/json"})
    p res
    p res.body
    maybe_parse_json(res)
  end


  def put_json(suffix, json)
    put_url = url(suffix)

    p put_url
    p json

    http_request(put_url) do |http|
      req = Net::HTTP::Put.new(put_url.request_uri)
      req['Content-type'] = 'text/json'
      req.body = json
      req.basic_auth @username, @password

      response = http.request(req)

      if response.code !~ /^2/
        raise "Failure in PUT request to onbase: #{response.body}"
      end

      p response.body

      response
    end
  end


  RecordStream = Struct.new(:content_type, :content_length, :body)

  def stream_record(onbase_id)
    get_url = url(onbase_id)

    http_request(get_url) do |http|
      req = Net::HTTP::Get.new(get_url.request_uri)

      req.basic_auth @username, @password

      http.request(req) do |resp|
        buffer = FileBuffer.new

        resp.read_body do |chunk|
          buffer << chunk
        end

        return RecordStream.new(resp['Content-Type'], resp['Content-Length'], buffer)
      end
    end

    # If all else fails...
    nil
  end


  def add_to_keywords(onbase_id, keywords)
    onbase_keywords = get_keywords(onbase_id)

    merged = onbase_keywords.merge('keywords' => merge_keywords(onbase_keywords['keywords'], format_keywords(keywords)))
    p put_keywords(onbase_id, merged)
  end


  def get_keywords(onbase_id)
    get_json("#{onbase_id}/keywords")
  end

  def put_keywords(onbase_id, keywords)
    put_json("#{onbase_id}/keywords", keywords.to_json)
  end


  private


  def url(suffix, params = {})
    s = "#{@base_url}/#{suffix}".gsub(/\/+$/, '')
    uri = URI(s)
    uri.query = URI.encode_www_form(params.merge('logUser' => @user))

    uri
  end


  def merge_keywords(*keywords)
    # Previously we had a .reverse before the uniq to favor keeping the more
    # recent keywords, but this messes up the "current_date" keyword, so we took
    # it out.  Now when a keyword is set it stays set and can't be overridden.
    keywords.reduce {|k1, k2| k1 + k2}.uniq {|k| k['keywordTypeName']}
  end


  def format_keywords(keywords)
    keywords.map do |name, value|
      {
        "keywordTypeName" => name,
        "keywordValue" => value
      }
    end
  end


  def http_request(url)
    Net::HTTP.start(url.host, url.port,
                    :use_ssl => url.scheme == 'https',
                    :read_timeout => 300,
                    :open_timeout => 300) do |http|
      yield(http)
    end
  end

end
