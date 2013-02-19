require 'bundler'
Bundler.require

configure do
  set server: 'thin'
  set connections: {}
  enable :sessions
end

helpers do
  def assign_session
    session[:id] ||= SecureRandom.uuid
  end

  def add_connection(connection)
    settings.connections[session[:id]] = connection
  end

  def remove_connection(connection)
    settings.connections.delete_if { |_, v| v == connection }
  end

  def other_connections
    Hash[settings.connections.reject { |k, _| k == session[:id] }].values
  end

  def event(data)
    "data: #{data}\n\n"
  end
end

before do
  assign_session
end

get '/' do
  erb :peerconnection
end

get '/stream', provides: 'text/event-stream' do
  stream(:keep_open) { |out|
    add_connection(out)
    out.callback { remove_connection(out) }
  }
end

post '/' do
  message = event(request.body.read)
  other_connections.each { |out| out << message }
  204
end

get '/mediastreams' do
  erb :mediastreams
end

__END__

@@ peerconnection
<!doctype html>
<html>
  <head>
    <title>Peer Connections</title>
    <script type="text/javascript">
      window.onload = function() {
        function ServerConnection() {
          this.send = function(message) {
            request = new XMLHttpRequest()
            request.open('POST', '/', true)
            request.setRequestHeader('Content-Type', 'application/json')
            request.send(JSON.stringify(message))
          }

          this.source = new EventSource('/stream')

          var that = this
          this.source.addEventListener('message', function(event) {
            that.onmessage(event.data)
          }, false);
        }

        var connection = null
        var started = false
        var server = new ServerConnection()

        server.onmessage = function(message) {
          message = JSON.parse(message)
          console.log(message)

          switch(message.type) {
            case 'offer':
              if(!started) { openConnection() }
              connection.setRemoteDescription(new RTCSessionDescription(message))
              connection.createAnswer(function(sessionDescription) {
                connection.setLocalDescription(sessionDescription)
                server.send(sessionDescription)
              })
              break
            case 'answer':
              connection.setRemoteDescription(new RTCSessionDescription(message))
              break
            case 'candidate':
              connection.addIceCandidate(new RTCIceCandidate({
                sdpMLineIndex: message.label,
                candidate: message.candidate
              }))
              break
          }
        }

        connection = new webkitRTCPeerConnection({ iceServers: [{ url: 'stun:stun.l.google.com:19302' }] })

        connection.onicecandidate = function(event) {
          if(event.candidate) {
            server.send({
              type: 'candidate',
              label: event.candidate.spdMLineIndex,
              id: event.candidate.sdpMid,
              candidate: event.candidate.candidate
            })
          }
        }

        connection.onaddstream = function(event) {
          video.src = URL.createObjectURL(event.stream)
        }

        function openConnection() {
          started = true

          connection.createOffer(function(sessionDescription) {
            connection.setLocalDescription(sessionDescription)
            server.send(sessionDescription)
          })
        }

        function onUserMediaSuccess(stream) {
          connection.addStream(stream)
          openConnection()
        }

        navigator.webkitGetUserMedia({ audio: true, video: true }, onUserMediaSuccess, null)
      }
    </script>
  </head>
  <body>
    <video id="video" autoplay="autoplay"></video>
  </body>
</html>

@@ mediastreams
<!doctype html>
<html>
  <head>
    <title>Media Streams</title>
    <script type="text/javascript">
      window.onload = function() {
        function onUserMediaSuccess(stream) {
          video.src = URL.createObjectURL(stream)
        }

        function onUserMediaError(stream) {
          console.log('Oops something went wrong!')
        }

        navigator.webkitGetUserMedia({ audio: true, video: true }, onUserMediaSuccess, onUserMediaError)
      }
    </script>
  </head>
  <body>
    <video id="video" autoplay="autoplay"></video>
  </body>
</html>
