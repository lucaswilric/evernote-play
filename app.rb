# Load libraries required by the Evernote OAuth
require 'oauth'
require 'oauth/consumer'
  
# Load Thrift & Evernote Ruby libraries
require 'evernote_oauth'
require 'app_configuration'
 
enable :sessions

before do
  @config = AppConfiguration.new('.config.yml')

  if @config.evernote_oauth_key.empty? || @config.evernote_oauth_secret.empty?
          halt '<span style="color:red">Before using this sample code you must edit evernote_config.rb and replace OAUTH_CONSUMER_KEY and OAUTH_CONSUMER_SECRET with the values that you received from Evernote. If you do not have an API key, you can request one from <a href="http://dev.evernote.com/documentation/cloud/">dev.evernote.com/documentation/cloud/</a>.</span>'
  end
end

helpers do
  def client
    @client ||= EvernoteOAuth::Client.new(token: auth_token, consumer_key: @config.evernote_oauth_key, consumer_secret: @config.evernote_oauth_secret, sandbox: @config.evernote_sandbox)
  end

  def auth_token
    session[:access_token].token if session[:access_token]
  end

  def user_store
    @user_store ||= client.user_store
  end
 
  def note_store
    @note_store ||= client.note_store
  end

  def en_user
    user_store.getUser(auth_token)
  end

  def notebooks
    @notebooks ||= note_store.listNotebooks(auth_token)
  end

  def total_note_count
    filter = Evernote::EDAM::NoteStore::NoteFilter.new
    counts = note_store.findNoteCounts(auth_token, filter, false)
    notebooks.inject(0) do |total_count, notebook|
      total_count + (counts.notebookCounts[notebook.guid] || 0)
    end
  end
end

configure do
  set :conf, AppConfiguration.new('.config.yml')
end

get '/' do
  @access_token = session[:access_token]
  erb :index
end

get '/reset' do
  session.clear
  redirect '/'
end

get '/list' do
  begin
    # Get notebooks
    session[:notebooks] = notebooks.map(&:name)
    # Get username
    session[:username] = en_user.username
    # Get total note count
    #session[:total_notes] = total_note_count
    erb :index
# rescue => e
#   @last_error = "Error listing notebooks: #{e.message}"
#   erb :error
  end
end

get '/requesttoken' do
  callback_url = request.url.chomp("requesttoken").concat("callback")
  begin
    session[:request_token] = client.request_token(:oauth_callback => callback_url)
    redirect '/authorize'
# rescue => e
#   @last_error = "Error obtaining temporary credentials: #{e.message}"
#   erb :error
  end
end

get '/authorize' do
  if session[:request_token]
    redirect session[:request_token].authorize_url
  else
    # You shouldn't be invoking this if you don't have a request token
    @last_error = "Request token not set."
    erb :error
  end
end

get '/callback' do
  unless params['oauth_verifier'] || session['request_token']
    @last_error = "Content owner did not authorize the temporary credentials"
    halt erb :error
  end

  session[:oauth_verifier] = params['oauth_verifier']

  begin
    session[:access_token] = session[:request_token].get_access_token(:oauth_verifier => session[:oauth_verifier])
    redirect '/list'
  rescue => e
    @last_error = 'Error extracting access token'
    erb :error
  end
end

get '/save/:content' do
  template = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note><p>{content}</p><en-media type="application/pdf" hash="{hash}" /></en-note>'

  raise "Not authorised." unless session[:access_token] 

  filename = '/Users/lucas/Documents/Android intro.pdf'
  pdf = File.open(filename, "rb") { |io| io.read }

  hashFunc = Digest::MD5.new
  hashHex = hashFunc.hexdigest(pdf)

  data = Evernote::EDAM::Type::Data.new()
  data.size = pdf.size
  data.bodyHash = hashHex
  data.body = pdf;

  resource = Evernote::EDAM::Type::Resource.new()
  resource.mime = "application/pdf"
  resource.data = data;
  resource.attributes = Evernote::EDAM::Type::ResourceAttributes.new()
  resource.attributes.fileName = filename.split('/').last

  note = Evernote::EDAM::Type::Note.new(
    title: "Yep. It's a note.", 
    content: template.gsub('{content}', params[:content]).gsub('{hash}', hashHex), active: true
  )
  note.resources = [ resource ]

  note_store.createNote(auth_token, note)
end
