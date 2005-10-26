require 'rss/2.0'
require 'net/http'
require 'timeout'
require 'money'

class CurrencyConverter
  @@rates = {}
  @@rss_url = "http://currencysource.com/RSS/%s.xml"
  @@timeout = 10
  @@update_interval = 3.hours
  
  cattr_accessor :rss_url, :timeout, :update_interval, :rates
  
  def self.get_rate(from, to)
    from = from.to_s.upcase!
    to = to.to_s.upcase!
    fetch_data(from, to)
    
    if @@rates[from].has_key? to
      return @@rates[from][to]
    else
      raise Money::MoneyError.new("Don't know how to exchange from #{from} to #{to}!")
    end
  end
  
  def self.reduce(money, currency)
    Money.new( (money.cents * get_rate(money.currency, currency)).floor, currency.to_s.upcase )
  end
  
  private
  
  def self.fetch_data(from, to)
    @@rates[from] ||= {}
    return true if @@rates.has_key?(from) && @@rates[from].has_key?(to) && @@rates[from][:updated] > @@update_interval.ago

    res = nil
    return false unless Timeout::timeout(@@timeout) { res = Net::HTTP.get_response(URI.parse(@@rss_url % [from])) }
    return false unless res.code.to_i == 200

    rss = RSS::Parser.parse(res.body, false)
    return false if rss.nil?

    rss.items.each do |item|
      item.title =~ /1 #{from} = (\w\w\w) \(([\d\.,]+)\)/
      to = $1.to_s ; rate = $2.to_s
      rate = rate.gsub(',','').to_f
      @@rates[from][to] = rate
    end
    @@rates[from][:updated] = Time.now

    return true
  end

end
