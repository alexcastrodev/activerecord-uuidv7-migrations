```ruby
timestamp = (record.created_at.to_r * 1000).to_i
uuid = UUID7.generate(timestamp: (record.created_at.to_f * 1000).to_i)
# Logging the generated UUID and its timestamp for verification
timestamp_hex = uuid.delete('-')[0...12]
timestamp_ms = timestamp_hex.to_i(16)
extracted_time = Time.at(timestamp_ms / 1000.0)
puts "  Generated UUIDv7: #{uuid} with timestamp: #{extracted_time.utc} (original created_at: #{record.created_at.utc})"
```
