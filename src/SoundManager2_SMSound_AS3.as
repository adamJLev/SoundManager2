/*
   SoundManager 2: Javascript Sound for the Web
   ----------------------------------------------
   http://schillmania.com/projects/soundmanager2/

   Copyright (c) 2007, Scott Schiller. All rights reserved.
   Code licensed under the BSD License:
   http://www.schillmania.com/projects/soundmanager2/license.txt

   Flash 9 / ActionScript 3 version
*/

package
{

	import flash.events.*;
	import flash.external.*;
	import flash.media.Sound;
	import flash.media.SoundChannel;
	import flash.media.SoundLoaderContext;
	import flash.media.SoundMixer;
	import flash.media.SoundTransform;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.NetStreamPlayOptions;
	import flash.net.URLRequest;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	import flash.utils.getTimer;

	public class SoundManager2_SMSound_AS3 extends Sound
	{

		public var sm : SoundManager2_AS3 = null;
		// externalInterface references (for Javascript callbacks)
		public var baseJSController : String = "soundManager";
		public var baseJSObject : String = baseJSController + ".sounds";
		public var soundChannel : SoundChannel = new SoundChannel();
		public var urlRequest : URLRequest;
		public var soundLoaderContext : SoundLoaderContext;
		public var waveformData : ByteArray = new ByteArray();
		public var waveformDataArray : Array = [];
		public var eqData : ByteArray = new ByteArray();
		public var eqDataArray : Array = [];
		public var usePeakData : Boolean = false;
		public var useWaveformData : Boolean = false;
		public var useEQData : Boolean = false;
		public var sID : String;
		public var sURL : String;
		public var justBeforeFinishOffset : int;
		public var didJustBeforeFinish : Boolean;
		public var didFinish : Boolean;
		public var loaded : Boolean;
		public var connected : Boolean;
		public var failed : Boolean;
		public var paused : Boolean;
		public var finished : Boolean;
		public var duration : Number;
		public var handledDataError : Boolean = false;
		public var ignoreDataError : Boolean = false;
		public var autoPlay : Boolean = false;
		public var autoLoad : Boolean = false;
		public var pauseOnBufferFull : Boolean = false; // only applies to RTMP
		public var loops : Number = 1;
		public var lastValues : Object = {bytes: 0, position: 0, volume: 100, pan: 0, loops: 1, leftPeak: 0, rightPeak: 0, waveformDataArray: null, eqDataArray: null, isBuffering: null, bufferLength: 0};
		public var didLoad : Boolean = false;
		public var useEvents : Boolean = false;
		public var sound : Sound = new Sound();

		public var nc : NetConnection;
		public var ns : NetStream = null;
		public var st : SoundTransform;
		public var useNetstream : Boolean;
		public var bufferTime : Number = 3; // previously 0.1
		public var bufferTimes : Array; // an array of integers (for specifying multiple buffers)
		public var lastNetStatus : String = null;
		public var serverUrl : String = null;

		public var start_time : Number;
		public var connect_time : Number;
		public var play_time : Number;
		public var recordStats : Boolean = false;
		public var checkPolicyFile : Boolean = false;

		private var reconnecting : Boolean;
		private var _pendingConnection : Boolean;
		private var nsPlayOptions2 : NetStreamPlayOptions;

		private var _isLoading : Boolean;
		private var _loadProgressTimer : Timer = new Timer(500, 0);
		
		private var _closeTime:Number;
		private var _networkConnected:Boolean;
		//private var timedOut:Boolean;
		private var _unpaused:Boolean;
		
		public function SoundManager2_SMSound_AS3(oSoundManager : SoundManager2_AS3, netconnection:NetConnection, sIDArg : String=null, sURLArg : String=null, usePeakData : Boolean=false, useWaveformData : Boolean=false, useEQData : Boolean=false, useNetstreamArg : Boolean=false, netStreamBufferTime : Number=1, serverUrl : String=null, duration : Number=0, autoPlay : Boolean=false, useEvents : Boolean=false, bufferTimes : Array=null, recordStats : Boolean=false, autoLoad : Boolean=false, checkPolicyFile : Boolean=false)
		{
			this.sm = oSoundManager;
			this.nc = netconnection;
			this.sID = sIDArg;
			this.sURL = sURLArg;
			this.usePeakData = usePeakData;
			this.useWaveformData = useWaveformData;
			this.useEQData = useEQData;
			this.urlRequest = new URLRequest(sURLArg);
			this.justBeforeFinishOffset = 0;
			this.didJustBeforeFinish = false;
			this.didFinish = false; // non-MP3 formats only
			this.loaded = false;
			this.connected = false;
			this.failed = false;
			this.finished = false;
			this.soundChannel = null;
			this.lastNetStatus = null;
			this.useNetstream = useNetstreamArg;
			this.serverUrl = serverUrl;
			this.duration = duration;
			this.recordStats = recordStats;
			this.useEvents = useEvents;
			this.autoLoad = autoLoad;
			if (netStreamBufferTime)
			{
				this.bufferTime = netStreamBufferTime;
			}
			// Use bufferTimes instead of bufferTime
			if (bufferTimes !== null)
			{
				this.bufferTimes = bufferTimes;
			}
			else
			{
				this.bufferTimes = [this.bufferTime];
			}
			if (recordStats)
			{
				this.start_time = getTimer();
			}
			this.checkPolicyFile = checkPolicyFile;

			writeDebug('SoundManager2_SMSound_AS3: Got duration: ' + duration + ', autoPlay: ' + autoPlay);

			if (this.useNetstream){
				if( !this.nc.connected ){
					connect();
				}else{
					connectSuccess();
				}
			}else{
				this.connect_time = this.start_time;
				//this doesnt make sense. but keeping it here.
				this.connected = true;
			}

		}

		private function connect() : void
		{
			// Pause on buffer full if auto-loading an RTMP stream
			if (this.serverUrl && this.autoLoad)
			{
				//this.pauseOnBufferFull = true;
			}

			// TODO: security/IO error handling
			// this.nc.addEventListener(SecurityErrorEvent.SECURITY_ERROR, doSecurityError);
			nc.addEventListener(NetStatusEvent.NET_STATUS, onNetConnectionStatus);

			if( !this.sm.ncfirstRun ){
				//reconnect();
				_pendingConnection = true;
			}
			
			writeDebug('SoundManager2_SMSound_AS3: NetConnection: connecting to server ' + this.serverUrl + '...');
			this.nc.connect(serverUrl);
		}

		//used for cases when the connection is dropped
		public function reconnect() : void
		{
      		writeDebug('SoundManager2_SMSound_AS3: Reconnecting to server ');
			reconnecting = true;
			this.nc.connect(serverUrl);
		}
		
		public function resumeStream() : void
		{
			writeDebug('SoundManager2_SMSound_AS3: in resume');
			paused = false;
			ns.resume();
		}
		
		
		//TODO: all of this shouldn't be in this function...
		//wanted to name createStream but the
		//js side may be needing parts of this...
		private function connectSuccess():void{
			this.ns = new NetStream(this.nc);
			this.ns.checkPolicyFile = this.checkPolicyFile;
			// bufferTime reference: http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/net/NetStream.html#bufferTime
			this.ns.bufferTime = getStartBuffer(); // set to 0.1 or higher. 0 is reported to cause playback issues with static files.
			this.st = new SoundTransform();
			this.ns.client = this;
			this.ns.receiveAudio(true);
			this.addNetstreamEvents();
			this.failed = false;
			this.connected = true;
			_networkConnected = true;
			
			if (recordStats)
			{
				this.recordConnectTime();
			}
			if (this.useEvents)
			{
				writeDebug('firing _onconnect for ' + this.sID);
				ExternalInterface.call(this.sm.baseJSObject + "['" + this.sID + "']._onconnect", 1);
			}
			if( _pendingConnection ){
				_pendingConnection = false;
				writeDebug('_pendingConnection false ');
				loadSound( sURL );
				//start( 0, 1 );
			}
			if (reconnecting)
			{
  				writeDebug('reconnecting ' + this.sID);
				ns.play( this.sURL );
			}
		}

		public function onNetConnectionStatus(event : NetStatusEvent) : void
		{
			if (this.useEvents)
			{
				writeDebug('onNetConnectionStatus: ' + event.info.code);
			}

			switch (event.info.code)
			{

				case "NetConnection.Connect.Success":
					writeDebug('NetConnection: connected');
					try
					{
						connectSuccess();
					}
					catch (e : Error)
					{
						this.failed = true;
						writeDebug('netStream error: ' + e.toString());
						ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Connection failed!', event.info.level, event.info.code);
					}
					break;

				// This is triggered when the sound loses the connection with the server.
				// In some cases one could just try to reconnect to the server and resume playback.
				// However for streams protected by expiring tokens, I don't think that will work.
				//
				// Flash says that this is not an error code, but a status code...
				// should this call the onFailure handler?
				case "NetConnection.Connect.Closed":
					this.failed = true;
					if(this.ns) _closeTime = this.ns.time;
					this.connected = false;
					//if( !this.timedOut ){
						ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Connection closed!', event.info.level, event.info.code);
						writeDebug("NetConnection: Connection closed!");
					//}
					/*else{
						writeDebug("NetConnection: Connection closed by Timeout. Ignoring...");
					}*/
					break;

				// Couldn't establish a connection with the server. Attempts to connect to the server
				// can also fail if the permissible number of socket connections on either the client
				// or the server computer is at its limit.  This also happens when the internet
				// connection is lost.
				case "NetConnection.Connect.Failed":
					this.failed = true;
					writeDebug("NetConnection: Connection failed! Lost internet connection? Try again... Description: " + event.info.description);
					ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", 'Connection failed!', event.info.level, event.info.code);
					break;

				// AJL: Experimental
				case "NetConnection.Connect.IdleTimeOut":
					this.failed = true;
					//this.timedOut = true;
					writeDebug("NetConnection: got IdleTimeOut '" + event.info.code + "'! Description: " + event.info.description);
					break;

				// A change has occurred to the network status. This could mean that the network
				// connection is back, or it could mean that it has been lost...just try to resume
				// playback.

				// KJV: Can't use this yet because by the time you get your connection back the
				// song has reached it's maximum retries, so it doesn't retry again.  We need
				// a new _ondisconnect handler.
				case "NetConnection.Connect.NetworkChange":
				//  this.failed = true;
				//  writeDebug("NetConnection: Network connection status changed");
				  ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onnetworkchange", 'Reconnecting...');
				  _networkConnected = !_networkConnected;
				  
				  if( _networkConnected ){
					  _closeTime = ns.time;
					  _pendingConnection = true;
					  reconnect();
				  }					  
				  break;

				// Consider everything else a failure...
				default:
					this.failed = true;
					writeDebug("NetConnection: got unhandled code '" + event.info.code + "'! Description: " + event.info.description);
					ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", '', event.info.level, event.info.code);
					break;
			}

		}
		
		// Set the buffer size on the current NetSream instance to <tt>buffer</tt> secs
		// Only set the buffer if it's different to the current buffer.
		public function setBuffer(buffer : int) : void
		{
			if (this.ns && buffer != this.ns.bufferTime)
			{
				this.ns.bufferTime = buffer;
				writeDebug('set buffer to ' + this.ns.bufferTime + ' secs');
			}
		}

		// Return the size of the starting buffer.
		public function getStartBuffer() : int
		{
			return this.bufferTimes[0];
		}

		// Return the size of the next buffer, given the size of the current buffer.
		// If there are no more buffers, returns the current buffer size.
		public function getNextBuffer(current_buffer : int) : int
		{
			var i : int = bufferTimes.indexOf(current_buffer);
			if (i == -1)
			{
				// Couldn't find the buffer, start from the start buffer size
				return getStartBuffer();
			}
			else if (i + 1 >= bufferTimes.length)
			{
				// Last (or only) buffer, keep the current buffer
				return current_buffer;
			}
			else
			{
				return this.bufferTimes[i + 1];
			}
		}

		public function writeDebug(s : String, bTimestamp : Boolean=false) : Boolean {
			return this.sm.writeDebug(s, bTimestamp); // defined in main SM object
		}

		public function onMetaData(infoObject : Object) : void
		{
			if (sm.debugEnabled)
			{
				var data : String = new String();
				for (var prop : * in infoObject)
				{
					data += prop + ': ' + infoObject[prop] + ' \n';
				}
				writeDebug('Metadata: ' + data);
			}
			this.duration = infoObject.duration * 1000;
			if (!this.loaded)
			{
				// writeDebug('not loaded yet: '+this.ns.bytesLoaded+', '+this.ns.bytesTotal+', '+infoObject.duration*1000);
				// TODO: investigate loaded/total values
				// ExternalInterface.call(baseJSObject + "['" + this.sID + "']._whileloading", this.ns.bytesLoaded, this.ns.bytesTotal, infoObject.duration*1000);
				ExternalInterface.call(baseJSObject + "['" + this.sID + "']._whileloading", this.bytesLoaded, this.bytesTotal, (infoObject.duration || this.duration))
			}
		}

		public function getBytesLoaded() : int
		{
			return this.bytesLoaded;
		}

		public function getWaveformData() : void
		{
			// http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundMixer.html#computeSpectrum()
			SoundMixer.computeSpectrum(this.waveformData, false, 0); // sample wave data at 44.1 KHz
			this.waveformDataArray = [];
			for (var i : int = 0, j : int = this.waveformData.length / 4; i < j; i++)
			{ // get all 512 values (256 per channel)
				this.waveformDataArray.push(int(this.waveformData.readFloat() * 1000) / 1000);
			}
		}

		public function getEQData() : void
		{
			// http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundMixer.html#computeSpectrum()
			SoundMixer.computeSpectrum(this.eqData, true, 0); // sample EQ data at 44.1 KHz
			this.eqDataArray = [];
			for (var i : int = 0, j : int = this.eqData.length / 4; i < j; i++)
			{ // get all 512 values (256 per channel)
				this.eqDataArray.push(int(this.eqData.readFloat() * 1000) / 1000);
			}
		}

		public function testPlay() : void
		{
			this.ns.play(this.sURL, 0);
			//_loadProgressTimer.addEventListener(TimerEvent.TIMER, onLoadProgressTick);
			_isLoading = true;
			_loadProgressTimer.start();
		}

		public function start(nMsecOffset : int, nLoops : int) : void
		{
			this.useEvents = true;
			if (this.sm.ncfirstRun && this.connected && this.useNetstream && this.nc.connected )
			{

				writeDebug("SMSound::start nMsecOffset " + nMsecOffset + ' nLoops ' + nLoops + ' current bufferTime ' + this.ns.bufferTime + ' current bufferLength ' + this.ns.bufferLength + ' this.lastValues.position ' + this.lastValues.position);

				// Don't seek if we don't have to because it destroys the buffer
				var set_position : Boolean = this.lastValues.position != null && this.lastValues.position != nMsecOffset;
				if (set_position)
				{
					// Minimize the buffer so playback starts ASAP
					this.setBuffer(this.getStartBuffer());
				}

				if (this.paused){
					writeDebug('start: resuming from paused state');
					this.ns.resume(); // get the sound going again
					if (!this.didLoad) {
					  this.didLoad = true;
					}
					this.paused = false;
				}else{
					if (!this.didLoad)
					{
						writeDebug('start: !didLoad - playing ' + this.sURL);
						this.didLoad = true;
						this.paused = false;
					}else{
						// previously loaded, perhaps stopped/finished. play again?
						writeDebug('playing again (not paused, didLoad = true)');
					}
					this.ns.play(this.sURL, 0);
					this.pauseOnBufferFull = false; // SAS: playing behaviour overrides buffering behaviour
				}

				// KJV seek after calling play otherwise some streams get a NetStream.Seek.Failed
				// Should only apply to the !didLoad case, but do it for all for simplicity.
				// nMsecOffset is in milliseconds for streams but in seconds for progressive
				// download.
				/*if (set_position)
				{
					writeDebug('set position seek: this.lastValues.position: ' + this.lastValues.position);
					this.ns.seek(this.serverUrl ? nMsecOffset / 1000 : nMsecOffset);
					this.lastValues.position = nMsecOffset; // https://gist.github.com/1de8a3113cf33d0cff67
				}*/

				this.applyTransform();

			}else if( (!this.sm.ncfirstRun || !this.connected || (this.nc && !this.nc.connected) ) && this.useNetstream ){
				_pendingConnection = true;
				writeDebug( "pendingConnection, ncfirstRun "+ sm.ncfirstRun +" connected: " + this.connected +"nc.connected: " + this.nc.connected );
			}
			else if( !this.useNetstream )
			{
				// writeDebug('start: seeking to '+nMsecOffset+', '+nLoops+(nLoops==1?' loop':' loops'));
				this.soundChannel = this.play(nMsecOffset, nLoops);
				this.addEventListener(Event.SOUND_COMPLETE, _onfinish);
				this.applyTransform();
			}
			
		}

		private function _onfinish() : void
		{
			this.removeEventListener(Event.SOUND_COMPLETE, _onfinish);
		}

		public function loadSound(sURL : String) : void
		{
			if (this.useNetstream)
			{
				if( this.connected && this.nc.connected ){
					this.useEvents = true;
					if (this.didLoad != true)
					{
						this.ns.play( this.sURL ); // load streams by playing them
						if (!this.autoPlay)
						{
							this.pauseOnBufferFull = true;
						}
						this.paused = false;
					}
					this.applyTransform();
				}else{
					_pendingConnection = true;
				}
			}
			else
			{
				try
				{
					this.didLoad = true;
					this.urlRequest = new URLRequest(sURL);
					this.soundLoaderContext = new SoundLoaderContext(1000, this.checkPolicyFile); // check for policy (crossdomain.xml) file on remote domains - http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundLoaderContext.html
					this.load(this.urlRequest, this.soundLoaderContext);
				}
				catch (e : Error)
				{
					writeDebug('error during loadSound(): ' + e.toString());
				}
			}
		}

		// Set the value of autoPlay
		public function setAutoPlay(autoPlay : Boolean) : void
		{
			if (!this.serverUrl)
			{
				this.autoPlay = autoPlay;
			}
			else
			{
				this.autoPlay = autoPlay;
				if (this.autoPlay)
				{
					this.pauseOnBufferFull = false;
				}
				else if (!this.autoPlay)
				{
					this.pauseOnBufferFull = true;
				}
			}
		}

		public function setVolume(nVolume : Number) : void
		{
			this.lastValues.volume = nVolume / 100;
			this.applyTransform();
		}

		public function setPan(nPan : Number) : void
		{
			this.lastValues.pan = nPan / 100;
			this.applyTransform();
		}

		public function applyTransform() : void
		{
			var st : SoundTransform = new SoundTransform(this.lastValues.volume, this.lastValues.pan);
			if (this.useNetstream)
			{
				if (this.ns)
				{
					this.ns.soundTransform = st;
				}
				else
				{
					// writeDebug('applyTransform(): Note: No active netStream');
				}
			}
			else if (this.soundChannel)
			{
				this.soundChannel.soundTransform = st; // new SoundTransform(this.lastValues.volume, this.lastValues.pan);
			}
		}

		public function recordPlayTime() : void
		{
			this.play_time = Math.round(getTimer() - (this.start_time + this.connect_time));
			writeDebug('Play took ' + this.play_time + ' ms');
			// We must now have both stats, call the onstats callback
			ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onstats", {play_time: this.play_time, connect_time: this.connect_time});
			// Stop tracking any stats for this object
			this.recordStats = false;
		}

		public function recordConnectTime() : void
		{
			this.connect_time = Math.round(getTimer() - this.start_time);
			writeDebug('Connect took ' + this.connect_time + ' ms');
		}

		public function doIOError(e : IOErrorEvent) : void
		{
			ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onload", 0); // call onload, assume it failed.
			// there was a connection drop, a loss of internet connection, or something else wrong. 404 error too.
		}

		public function doAsyncError(e : AsyncErrorEvent) : void
		{
			writeDebug('asyncError: ' + e.text);
		}
		
		private function onNetStreamStatus(event : NetStatusEvent) : void
		{
			writeDebug(event.info.code);
			
			switch (event.info.code)
			{
				case "NetStream.Play.Reset":
					break;
				case "NetStream.Unpause.Notify":
					_unpaused = true;
					break;
				case "NetStream.Pause.Notify":
					_unpaused = false;
					break;
				case "NetStream.Play.Start":
					if( reconnecting ){
						ns.seek( _closeTime );
						_closeTime = 0;
						reconnecting = false;
					}
					break;
				case "NetStream.Buffer.Full":
					//TODO if autoplay=false, dont start buffering at all.
					break;
				case "NetStream.Buffer.Empty":
					ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onbufferchange", 0);
					//not sure we need/want Stop here.
					if( lastNetStatus == 'NetStream.Play.Stop' || lastNetStatus == 'NetStream.Buffer.Flush'){
						if (this.duration && (this.ns.time * 1000) < (this.duration - 5000))
						{
							writeDebug('Buffer.Empty but not end of stream. retry seeking to '+ (this.ns.time - 1) +'  (sID: ' + this.sID + ', time: ' + (this.ns.time * 1000) + ', duration: ' + this.duration + ')');
							if( ns.time > 2) ns.seek( ns.time - 1 );
						}else{
							//lame name.
							this.didJustBeforeFinish = false; // reset
							this.finished = true;
							writeDebug('calling onfinish for sound ' + this.sID);
							this.sm.checkProgress();
							ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfinish");
						}
					}
					if( bufferTimes.length > 1 ){
						setBuffer( getStartBuffer() );
					}
					break;
				case "NetStream.Buffer.Flush":
					break;
				case "NetStream.Play.Stop":
					break;
				case "NetStream.Play.Complete":
					this.didJustBeforeFinish = false; // reset
					this.finished = true;
					ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfinish");
					break;
				case "NetStream.Play.FileStructureInvalid":
				case "NetStream.Play.StreamNotFound":
					this.failed = true;
					ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfailure", '', event.info.level, event.info.code);
					break;
				case "NetStream.Seek.Notify":
					break;
				case "NetStream.InvalidArg":
					writeDebug('Handling NetStream.InvalidArg');
					break;
				default:
					break;
			}
			lastNetStatus = event.info.code;
		}

		// NetStream client callback. Invoked when the song is complete.
		public function onPlayStatus(info : Object) : void
		{
			writeDebug('onPlayStatus called with ' + info);
			switch (info.code)
			{
				case "NetStream.Play.Complete":
					this.didJustBeforeFinish = false; // reset
					this.finished = true;
					ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onfinish");
					//writeDebug('Song has finished!');
					break;
			}
		}

		// KJV The sound adds some of its own netstatus handlers so we don't need to do it here.
		public function addNetstreamEvents() : void
		{
			ns.addEventListener(AsyncErrorEvent.ASYNC_ERROR, doAsyncError);
			ns.addEventListener(NetStatusEvent.NET_STATUS, onNetStreamStatus);
			ns.addEventListener(IOErrorEvent.IO_ERROR, doIOError);
		}

		public function removeNetstreamEvents() : void
		{
			ns.removeEventListener(AsyncErrorEvent.ASYNC_ERROR, doAsyncError);
			ns.removeEventListener(NetStatusEvent.NET_STATUS, onNetStreamStatus);
			ns.removeEventListener(IOErrorEvent.IO_ERROR, doIOError);
			// KJV Stop listening for NetConnection events on the sound
			nc.removeEventListener(NetStatusEvent.NET_STATUS, onNetConnectionStatus);
		}

	}
}