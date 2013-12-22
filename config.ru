require 'rubygems'

begin
  require 'bundler'
  Bundler.require
  require './app'
  run Sinatra::Application
rescue LoadError => err
  warn "Where's Bundler? #{err}"
end