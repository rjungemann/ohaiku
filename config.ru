require 'net/http'
require 'unindent'
require 'moneta'
require 'odyssey'
require 'sinatra/base'

# USAGE:
#
#     examples =  %[
#       An old silent pond...
#       A frog jumps into the pond,
#       splash! Silence again.
#
#       A summer river
#       being crossed — how pleasing — with
#       sandals in my hands!
#
#       This is not a
#       haiku because it has too many
#       fucking syllables
#     ]
#
#     haikus = examples.unindent.strip.split("\n\n")
#     haikus.each do |haiku|
#       p [haiku, Ohaiku.haiku?(haiku)]
#     end
#
class Ohaiku
  class RedisCache
    def self.find(term)
      cache[term]
    end

    def self.add(term, result)
      cache[term] = result
    end

    def self.remove(term)
      cache.delete(term)
    end

    def self.clear
      cache.clear
    end

    def self.cache
      @cache ||= Moneta.new(:Redis, server: ENV['REDIS_URL'] || 'localhost:6379')
    end
  end

  CACHE = RedisCache
  API_KEY = ENV['MW_SD4_API_KEY'] || '64646753-ff4c-4276-ad6f-199a9224c899'

  def self.fetch(word)
    cached = CACHE.find(word)
    return cached if cached
    puts 'Did not hit cache.'
    url = "http://www.dictionaryapi.com/api/v1/references/collegiate/xml/#{word}?key=#{API_KEY}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    response = http.request(Net::HTTP::Get.new(uri.request_uri))
    body = response.body
    CACHE.add(word, body)
    body
  end

  def self.dictionary_syllable_count(word)
    match = fetch(word).match(/<pr>(.*?)<\/pr>/) || []
    phonetics = match[1]
    return nil unless phonetics
    phonetics
      .split(',')
      .map { |n| n.strip }
      .reject { |n| n.match(/^-|-$/) }
      .map { |n| n.split('-').count }
  end

  def self.computed_syllable_count(word)
    Odyssey.flesch_kincaid_re(word, true)['syllable_count']
  end

  def self.haiku?(haiku)
    haiku = haiku
      .split("\n")
      .map { |line| line.gsub(/[^A-Za-z ]/, '').gsub(/\s+/, ' ').split(' ') }
    return false unless haiku.length == 3
    sums = haiku.map { |line|
      line.inject([0, 0]) { |sums, word|
        syllables_list = dictionary_syllable_count(word) + [computed_syllable_count(word)]
        sums[0] += syllables_list.min
        sums[1] += syllables_list.max
        sums
      }
    }
    return false unless (sums[0][0]..sums[0][1]).include?(5)
    return false unless (sums[1][0]..sums[1][1]).include?(7)
    return false unless (sums[2][0]..sums[2][1]).include?(5)
    true
  end

  class App < Sinatra::Base
    get '/' do
      %[
        <!DOCTYPE html>
        <html>
          <head>
            <title>Ohaiku: Is it a haiku?</title>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/tether/1.3.7/js/tether.min.js"></script>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.0.0-alpha.5/css/bootstrap-flex.min.css">
            <style>
              .alert-success,
              .alert-danger {
                display: none;
              }
            </style>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.0.0-alpha.5/js/bootstrap.min.js"></script>
          </head>
          <body>
            <div class="container">
              <div class="row">
                <div class="col-md-12">
                  <h1 class="display-1">
                    Ohaiku
                  </h1>
                  <p class="lead">Is it a haiku? Find out!</h2>
                  <div class="alerts">
                    <div class="alert alert-success" role="alert">It's probably a haiku!</div>
                    <div class="alert alert-danger" role="alert">It's probably not a haiku!</div>
                  </div>
                  <form method="POST" "/">
                    <p>
                      <label for="haiku" hidden>Haiku</label>
                      <textarea class="form-control" id="haiku" rows="3" placeholder="Insert haiku here..."></textarea>
                    </p>
                    <p>
                      <button type="submit">Submit</button>
                    </p>
                  </form>
                </div>
              </div>
              <div class="row">
                <div class="col-md-12">
                  <hr>
                  Brought to you by <a href="http://teamsketchy.com">Team Sketchy</a>.
                </div>
              </div>
            </div>
            <script>
              $('form').submit(function (e) {
                $('#haiku').prop('disabled', true);
                $('form [type=submit]').prop('disabled', true);
                var data = {
                  haiku: $('#haiku').val()
                };
                $.post('/', data, function (data) {
                  $('#haiku').prop('disabled', false);
                  $('form [type=submit]').prop('disabled', false);
                  if (data === 'true') {
                    $('.alert-success').show();
                    $('.alert-danger').hide();
                  } else {
                    $('.alert-success').hide();
                    $('.alert-danger').show();
                  }
                })
                e.preventDefault();
              });
            </script>
          </body>
        </html>
      ]
    end

    post '/' do
      return 'false' if !params[:haiku] || params[:haiku].empty?
      Ohaiku.haiku?(params[:haiku]).to_s
    end
  end
end

run Ohaiku::App.new
