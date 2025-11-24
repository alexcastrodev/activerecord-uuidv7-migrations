require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'activerecord'
  gem 'pg'
  gem 'testcontainers'
  gem 'base64'
end

require 'testcontainers'
require 'active_record'

PGPORT = 5132

# Inicializa o container do PostgreSQL
puts "Starting PostgreSQL container..."
$postgres = Testcontainers::DockerContainer.new("postgres:18.1")
  .with_env("POSTGRES_PASSWORD", "postgres")
  .with_env("POSTGRES_USER", "postgres")
  .with_env("POSTGRES_DB", "test_db")
  .with_env("PGPORT", PGPORT.to_s)
  .with_exposed_port(PGPORT)

$postgres.start

# Configura a conexão
host = $postgres.host
port = $postgres.mapped_port(PGPORT)

# Aguarda o container estar pronto e tenta conectar com retry
puts "Waiting for PostgreSQL to be ready at #{host}:#{port}..."
max_retries = 30
retry_count = 0

loop do
  begin
    ActiveRecord::Base.establish_connection(
      adapter: 'postgresql',
      host: host,
      port: port,
      database: 'test_db',
      username: 'postgres',
      password: 'postgres',
      connect_timeout: 2
    )
    ActiveRecord::Base.connection.execute('SELECT 1')
    puts "✓ Connected successfully!"
    break
  rescue PG::ConnectionBad, ActiveRecord::ConnectionNotEstablished => e
    retry_count += 1
    if retry_count >= max_retries
      puts "✗ Failed to connect after #{max_retries} attempts"
      raise e
    end
    print "."
    sleep 1
  end
end

class Product < ActiveRecord::Base
end