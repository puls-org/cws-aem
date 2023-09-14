require 'json'
require 'aws-sdk-dynamodb'
require 'net/http'
require 'uri'
require './utils'
require 'time'

$dynamodb = Aws::DynamoDB::Client.new

def fetch_translations(filter_keys = [])
    translations = {}
    threads_pool = []
    CHANEL_DICTIONARIES_URLS.each_pair do |locale, url|
        threads_pool << Thread.new do
            begin
                start_time = Time.now.to_f
                content = get(url)
                end_time = Time.now.to_f
                elapsed_time = end_time - start_time
                if !content
                    next
                end

                translation_keys = JSON::parse(content)
                puts "Fetched content for #{url} (#{translation_keys.keys.size} keys) in #{elapsed_time}s"
                translation_keys.each_pair do |i18n_key, i18n_value|
                    if filter_keys.size > 0 and not filter_keys.include?(i18n_key)
                        next
                    end
                    translations[i18n_key] ||= {}
                    translations[i18n_key][locale] = i18n_value
                end
            rescue Exception => e
                puts e
                break
            end
        end
    end
            # Wait for all threads to finish
    threads_pool.each(&:join)
    return translations
end

def format_data(translations)
    translations_formated = {}
    translations.each_pair do |locale, value|
        translations_formated[locale] = value
    end
    translations_formated
end
def prepare_batch(translation_keys, filter_keys = [])
    batchs = []
    batch_count = 25.0

    i = 0

    tkeys = translation_keys.keys
    puts "Keys to prepare #{tkeys.size}"
    limit = tkeys.size
    while i < limit
        translation_key = tkeys[i]
        if filter_keys.size > 0 and not filter_keys.include?(translation_key)
            next
        end
        translations_locales = format_data(translation_keys[translation_key])
        batch_idx = (i / batch_count).floor
        batchs[batch_idx] ||= []
        batchs[batch_idx] << {
            "i18n_key": "#{translation_key}",
        }.merge(translations_locales)
        i += 1
    end
    return batchs
rescue Exception => e
    puts e
    return []
end

def update_batch(batch)
    req = batch.map do |item|
        {
            put_request: {
                item: item
            }
        }
    end

    params = {
        request_items: {
            "aemDictionary" => req
        }
    }
    $dynamodb.batch_write_item(params)
end
def get(url)
    # Define the URL you want to make a request to
    url = URI.parse(url)
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = (url.scheme == 'https')
    request = Net::HTTP::Get.new(url.request_uri)
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
        raise Exception.new "Error to get url %" % url
    end
    return response.body.force_encoding("UTF-8")
end
def lambda_handler(event:, context:)

    keysToUpdate = event["keysToUpdate"]
    tk = fetch_translations(keysToUpdate)
    batchs = prepare_batch(tk, keysToUpdate)
    batchs.each do |batch|
        update_batch(batch)
        puts "Updated #{batch.size} done"
    end
    {
        statusCode: 200,
        body: JSON.stringify(keysToUpdate),
    }
rescue Exception => e
    {
        statusCode: 502,
        body: {
            message: "#{e}"
        }
    }
end
# fetch_translations()

