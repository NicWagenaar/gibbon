require 'net/https'

module Gibbon
  class Export
    include Helpers

    attr_accessor :api_endpoint, :api_key, :timeout

    def initialize(api_endpoint: nil, api_key: nil, timeout: nil)
      @api_endpoint = api_endpoint ||  self.class.api_endpoint
      @api_key = api_key || self.class.api_key
      @timeout = timeout || self.class.timeout || 600
    end

    def list(params = {}, &block)
      call("list", params, &block)
    end

    def ecomm_orders(params = {}, &block)
      call("ecommOrders", params, &block)
    end

    def campaign_subscriber_activity(params = {}, &block)
      call("campaignSubscriberActivity", params, &block)
    end

    protected

    def export_api_url
      computed_api_endpoint = "https://#{get_data_center_from_api_key(@api_key)}api.mailchimp.com"
      "#{@api_endpoint || computed_api_endpoint}/export/1.0/"
    end

    def call(method, params = {}, &block)
      ensure_api_key

      rows = []

      api_url = export_api_url + method + "/"
      params = params.merge({ apikey: @api_key })
      block = Proc.new { |row| rows << row } unless block_given?

      url = URI.parse(api_url)
      req = Net::HTTP::Post.new(url.path, {'Content-Type' => 'application/json'})
      req.body = MultiJson.dump(params)
      Net::HTTP.start(url.host, url.port, read_timeout: @timeout, use_ssl: true) do |http|
        # http://stackoverflow.com/questions/29598196/ruby-net-http-read-body-nethttpokread-body-called-twice-ioerror
        http.request req do |response|
          i = -1
          last = ''
          response.read_body do |chunk|
            next if chunk.nil? or chunk.strip.empty?
            infix = "\n" if last[-1, 1]==']'
            lines, last = try_parse_line("#{last}#{infix}#{chunk}")
            lines.each { |line| block.call(line, i += 1) }
          end
          block.call(parse_line(last), i += 1) unless last.nil? or last.empty?
        end
      end
      rows unless block_given?
    end

    def try_parse_line(res)
      lines = res.split("\n")
      last = lines.pop || ''
      lines.map! { |line| parse_line(line) }
      [lines.compact, last]
    rescue MultiJson::ParseError
      [[], last]
    end


    def parse_line(line)
      MultiJson.load(line)
    rescue MultiJson::ParseError
      return []
    end

    private

    def ensure_api_key
      unless @api_key && @api_endpoint
        raise Gibbon::GibbonError, "You must set an api_key prior to making a call"
      end
    end

    class << self
      attr_accessor :api_endpoint, :api_key, :timeout

      def method_missing(sym, *args, &block)
        new(api_endpoint: self.api_endpoint, api_key: self.api_key, timeout: self.timeout).send(sym, *args, &block)
      end
    end
  end
end
