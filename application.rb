require 'bundler'
Bundler.require

configure do
  set server: 'thin'
  set connections: {}
  enable :sessions
end

get '/' do
  session[:id] ||= SecureRandom.uuid
  erb :peerconnection
end

get '/stream', provides: 'text/event-stream' do
  stream :keep_open do |out|
    settings.connections[session[:id]] = out
  end
end

post '/' do
  settings.connections.reject{ |k, _| k == session[:id] }.each { |_, out| out << "data: #{request.body.read}\n\n" }
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
        ServerConnection = function() {
          this.send = function(message) {
            request = new XMLHttpRequest()
            request.open('POST', '/', true)
            request.setRequestHeader('Content-Type', 'application/json')
            request.send(message)
          }

          this.source = new EventSource('/stream')

          var that = this

          this.source.addEventListener('message', function(event) {
            console.log(event)
            that.onmessage(event.data)
          }, false);
        }

        var connection = null
        var started = false
        var server = new ServerConnection()

        server.onmessage = function(message) {
          console.log(message)
          message = JSON.parse(message)

          switch(message.type) {
            case 'offer':
              console.log('receivedOffer')
              if(!started) { openConnection() }
              connection.setRemoteDescription(new RTCSessionDescription(message))
              connection.createAnswer(function(sessionDescription) {
                connection.setLocalDescription(sessionDescription)
                console.log('createAnswer')
                console.log(sessionDescription)
                server.send(JSON.stringify(sessionDescription))
              })
              break
            case 'answer':
              console.log('receivedAnswer')
              console.log(message)
              connection.setRemoteDescription(new RTCSessionDescription(message))
              break
            case 'candidate':
              console.log('receivedCandidate')
              console.log(message)
              candidate = new RTCIceCandidate({ 'sdpMLineIndex': message.label, 'candidate': message.candidate })
              connection.addIceCandidate(candidate)
              break
            default:
              console.log('receivedDefault')
              console.log(message)
              break
          }
        }

        connection = new webkitRTCPeerConnection({ 'iceServers': [{ 'url': 'stun:stun.l.google.com:19302' }] })

        connection.onicecandidate = function(event) {
          if(event.candidate) {
            console.log('onicecandidate')
            console.log(event.candidate)
            server.send(JSON.stringify({ type: 'candidate', label: event.candidate.spdMLineIndex, id: event.candidate.sdpMid, candidate: event.candidate.candidate }))
          }
        }

        connection.onaddstream = function(event) {
          console.log('onaddstream' + event)
          video.src = URL.createObjectURL(event.stream)
        }

        openConnection = function() {
          started = true
          console.log('openConnection')

          onUserMediaSuccess = function(stream) {
            console.log('addStream')
            connection.addStream(stream)
          }

          navigator.webkitGetUserMedia({ 'audio': true, 'video': true }, onUserMediaSuccess, null)

          connection.createOffer(function(sessionDescription) {
            connection.setLocalDescription(sessionDescription)
            console.log('createOffer')
            console.log(sessionDescription)
            server.send(JSON.stringify(sessionDescription))
          })
        }

        start.onclick = function() {
          openConnection()
          return false
        }
      }
    </script>
  </head>
  <body>
    <a id="start" href="#">Start Video</a>
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
        onUserMediaSuccess = function (stream) {
          video.src = URL.createObjectURL(stream)
        }

        onUserMediaError = function (stream) {
          console.log('Oops something went wrong!')
        }

        navigator.webkitGetUserMedia({ 'audio': true, 'video': true }, onUserMediaSuccess, onUserMediaError)
      }
    </script>
  </head>
  <body>
    <video id="video" autoplay="autoplay"></video>
  </body>
</html>
