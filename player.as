package
{
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageDisplayState;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.FullScreenEvent;
    import flash.events.MouseEvent;
    import flash.events.NetStatusEvent;
    import flash.events.TimerEvent;
    import flash.external.ExternalInterface;
    import flash.media.SoundTransform;
    import flash.media.Video;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.system.Security;
    import flash.utils.Timer;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;
	
    import flash.Stage;
    import flashx.textLayout.formats.Float;
    
    public class srs_player extends Sprite
    {
        // user set id.
        private var js_id:String = null;
        // user set callback
		private var IfClosed:String = null;
        private var js_on_player_ready:String = null;
        private var js_on_player_metadata:String = null;
        private var js_on_player_timer:String = null;
        private var js_on_player_empty:String = null;
		private var js_on_player_full:String = null;
		
        // play param url.
        private var user_url:String = null;
        // play param, user set width and height
        private var user_w:int = 0;
        private var user_h:int = 0;
        private var user_dar_den:int = 0;
        private var user_dar_num:int = 0;
        private var user_fs_refer:String = null;
        private var user_fs_percent:int = 0;
        
        private var media_conn:NetConnection = null;
        private var media_stream:NetStream = null;
        private var media_video:Video = null;
        private var media_metadata:Object = {};
        private var media_timer:Timer = new Timer(300);
        
        private var control_fs_mask:Sprite = new Sprite();
        
        public function srs_player()
        {
            if (!this.stage) {
                this.addEventListener(Event.ADDED_TO_STAGE, this.system_on_add_to_stage);
            } else {
                this.system_on_add_to_stage(null);
            }
        }
        private function system_on_add_to_stage(evt:Event):void {
            this.removeEventListener(Event.ADDED_TO_STAGE, this.system_on_add_to_stage);
            this.stage.align = StageAlign.TOP_LEFT;
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.addEventListener(FullScreenEvent.FULL_SCREEN, this.user_on_stage_fullscreen);
            this.stage.addEventListener(Event.RESIZE, this.do_resize);
            Security.allowDomain("*");
            
            this.addChild(this.control_fs_mask);
            this.control_fs_mask.buttonMode = true;
            this.control_fs_mask.addEventListener(MouseEvent.CLICK, user_on_click_video);
            
            
            var flashvars:Object = this.root.loaderInfo.parameters;
            
            if (!flashvars.hasOwnProperty("id")) {
                throw new Error("must specifies the id");
            }
            
            this.js_id = flashvars.id;
            this.js_on_player_ready = flashvars.on_player_ready;
            this.js_on_player_metadata = flashvars.on_player_metadata;
            this.js_on_player_timer = flashvars.on_player_timer;
			this.js_on_player_empty = flashvars.on_player_empty;
			this.js_on_player_full = flashvars.on_player_full;
            
            this.media_timer.addEventListener(TimerEvent.TIMER, this.system_on_timer);
            this.media_timer.start();
            
            flash.utils.setTimeout(this.system_on_js_ready, 0);
        }
        
        
        private function system_on_js_ready():void {
            if (!flash.external.ExternalInterface.available) {
                flash.utils.setTimeout(this.system_on_js_ready, 100);
                return;
            }
            
            flash.external.ExternalInterface.addCallback("__play", this.js_call_play);
            flash.external.ExternalInterface.addCallback("__stop", this.js_call_stop);
            flash.external.ExternalInterface.addCallback("__pause", this.js_call_pause);
			flash.external.ExternalInterface.addCallback("__resume", this.js_call_resume);
            flash.external.ExternalInterface.addCallback("__set_dar", this.js_call_set_dar);
            flash.external.ExternalInterface.addCallback("__set_fs", this.js_call_set_fs_size);
            flash.external.ExternalInterface.addCallback("__set_bt", this.js_call_set_bt);
            
            flash.external.ExternalInterface.call(this.js_on_player_ready, this.js_id);
        }
        

        private function system_on_timer(evt:TimerEvent):void {
			var ms:NetStream = this.media_stream;
			
            if (!ms) {
                return;
            }
			
			var rtime:Number = flash.utils.getTimer();
			var bitrate:Number = Number((ms.info.videoBytesPerSecond + ms.info.audioBytesPerSecond) * 8 / 1000);
            if(ms.bufferLength > 1) {
                js_call_resume();
            }
            flash.external.ExternalInterface.call(
                this.js_on_player_timer, this.js_id, ms.time, ms.bufferLength,
				bitrate, ms.currentFPS, rtime
			);
        }
		

		private function system_on_buffer_empty():void {
			var time:Number = flash.utils.getTimer();
			flash.external.ExternalInterface.call(this.js_on_player_empty, this.js_id, time);
		}
		private function system_on_buffer_full():void {
			var time:Number = flash.utils.getTimer();
			flash.external.ExternalInterface.call(this.js_on_player_full, this.js_id, time);
		}
        

        private function system_on_metadata(metadata:Object):void {
            this.media_metadata = metadata;
            
            var obj:Object = __get_video_size_object();
            
            obj.server = 'srs';
            obj.contributor = 'winlin';
            
            if (srs_server != null) {
                obj.server = srs_server;
            }
            if (srs_primary != null) {
                obj.contributor = srs_primary;
            }
            if (srs_authors != null) {
                obj.contributor = srs_authors;
            }
            
            var code:int = flash.external.ExternalInterface.call(js_on_player_metadata, js_id, obj);
            if (code != 0) {
                throw new Error("callback on_player_metadata failed. code=" + code);
            }
        }
        

        private function user_on_stage_fullscreen(evt:FullScreenEvent):void {
            if (!evt.fullScreen) {
                __execute_user_set_dar();
            } else {
                __execute_user_enter_fullscreen();
            }
        }
        private function do_resize(evt:Event):void {
            user_w = stage.stageWidth;
            user_h = stage.stageHeight;
            this.js_call_set_dar(-1, -1, user_w, user_h)
        }

        private function user_on_click_video(evt:MouseEvent):void {
            if (!this.stage.allowsFullScreen) {
                return;
            }
            
            // enter fullscreen to get the fullscreen size correctly.
            if (this.stage.displayState == StageDisplayState.FULL_SCREEN) {
                this.stage.displayState = StageDisplayState.NORMAL;
            } else {
                this.stage.displayState = StageDisplayState.FULL_SCREEN;
            }
        }
        

        private function js_call_pause():void {
            if (this.media_stream) {
                this.media_stream.pause();
            }
        }
         

        private function js_call_resume():void {
            if (this.media_stream) {
                this.media_stream.resume();
            }
        }
        

        private function js_call_set_dar(num:int, den:int, width:int, height:int):void {
            user_dar_num = num;
            user_dar_den = den;
            user_w = width;
            user_h = height;
            
            flash.utils.setTimeout(__execute_user_set_dar, 0);
        }
        

        private function js_call_set_fs_size(refer:String, percent:int):void {
            user_fs_refer = refer;
            user_fs_percent = percent;
        }
        

        private function js_call_set_bt(buffer_time:Number):void {
            if (this.media_stream) {
                this.media_stream.bufferTime = 0.1;
            }
        }
        

        private function js_call_stop():void {
            if (this.media_video) {
                this.removeChild(this.media_video);
                this.media_video = null;
            }
            if (this.media_stream) {
                this.media_stream.close();
                this.media_stream = null;
            }
            if (this.media_conn) {
                this.media_conn.close();
                this.media_conn = null;
            }
        }
        
        private var srs_server:String = null;
        private var srs_primary:String = null;
        private var srs_authors:String = null;
        private var srs_id:String = null;
        private var srs_pid:String = null;
        private var srs_server_ip:String = null;
        

        private function js_call_play(url:String, _width:int, _height:int, buffer_time:Number, volume:Number):void {
            this.user_url = url;
            this.user_w = _width;
            this.user_h = _height;
            log("start to play url:");
            this.media_conn = new NetConnection();
            this.media_conn.client = {};
            this.media_conn.client.onBWDone = function():void {};
            this.media_conn.addEventListener(NetStatusEvent.NET_STATUS, function(evt:NetStatusEvent):void {
                trace ("NetConnection: code=" + evt.info.code);
                
                if (evt.info.hasOwnProperty("data") && evt.info.data) {
                    if (evt.info.data.hasOwnProperty("srs_server")) {
                        srs_server = evt.info.data.srs_server;
                    }
                    if (evt.info.data.hasOwnProperty("srs_primary")) {
                        srs_primary = evt.info.data.srs_primary;
                    }
                    if (evt.info.data.hasOwnProperty("srs_authors")) {
                        srs_authors = evt.info.data.srs_authors;
                    }
                    if (evt.info.data.hasOwnProperty("srs_id")) {
                        srs_id = evt.info.data.srs_id;
                    }
                    if (evt.info.data.hasOwnProperty("srs_pid")) {
                        srs_pid = evt.info.data.srs_pid;
                    }
                    if (evt.info.data.hasOwnProperty("srs_server_ip")) {
                        srs_server_ip = evt.info.data.srs_server_ip;
                    }
                 
                }

                media_stream = new NetStream(media_conn);
                media_stream.soundTransform = new SoundTransform(volume);
                media_stream.bufferTime = 0.1;
                media_stream.client = {};
                media_stream.client.onMetaData = system_on_metadata;
                media_stream.addEventListener(NetStatusEvent.NET_STATUS, function(evt:NetStatusEvent):void {
                    trace ("NetStream: code=" + evt.info.code);
                    if (evt.info.code == "NetStream.Video.DimensionChange") {
                        system_on_metadata(media_metadata);
                    } else if (evt.info.code == "NetStream.Buffer.Empty") {
						system_on_buffer_empty();
					} else if (evt.info.code == "NetStream.Buffer.Full") {
						system_on_buffer_full();
					}
                    
                });
                
                var streamName:String = url.substr(url.lastIndexOf("/") + 1);
                media_stream.play(streamName);
                if(!media_video) {   
                    media_video = new Video();
                } 
                media_video.width = _width;
                media_video.height = _height;
                media_video.attachNetStream(media_stream);
                media_video.smoothing = true;
                addChild(media_video);
                
                __draw_black_background(_width, _height);
                log('When you see this!,your flash player has down!');
                log('When you see this!,your flash player has down!' + media_video.toString());

                setChildIndex(media_video, 0);
                log('Child Length' + numChildren);
            });
            
            if (url.indexOf("http") == 0) {
                this.media_conn.connect(null);
            } else {
                var tcUrl:String = this.user_url.substr(0, this.user_url.lastIndexOf("/"));
                this.media_conn.connect(tcUrl);
            }
        }
    
        

        private function __get_video_size_object():Object {
            var obj:Object = {
                width: media_video.width,
                height: media_video.height
            };
            
            // override with metadata size.
            if (this.media_metadata.hasOwnProperty("width")) {
                obj.width = this.media_metadata.width;
            }
            if (this.media_metadata.hasOwnProperty("height")) {
                obj.height = this.media_metadata.height;
            }
            
            // override with codec size.
            if (media_video.videoWidth > 0) {
                obj.width = media_video.videoWidth;
            }
            if (media_video.videoHeight > 0) {
                obj.height = media_video.videoHeight;
            }
            
            return obj;
        }

        private function __execute_user_enter_fullscreen():void {
            if (!user_fs_refer || user_fs_percent <= 0) {
                return;
            }
            
            var obj:Object = __get_video_size_object();
            
            var den:int = user_dar_den;
            var num:int = user_dar_num;
            
            if (den == 0) {
                den = obj.height;
            }
            if (den == -1) {
                den = this.stage.fullScreenHeight;
            }
            
            if (num == 0) {
                num = obj.width;
            }
            if (num == -1) {
                num = this.stage.fullScreenWidth;
            }
                
            // for refer is screen.
            if (user_fs_refer == "screen") {
                obj = {
                    width: this.stage.fullScreenWidth,
                    height: this.stage.fullScreenHeight
                };
            }
            __update_video_size(num, den, 
				obj.width * user_fs_percent / 100, 
				obj.height * user_fs_percent / 100, 
				this.stage.fullScreenWidth, this.stage.fullScreenHeight
			);
        }
        

        private function __execute_user_set_dar():void {
            // get the DAR
            var den:int = user_dar_den;
            var num:int = user_dar_num;
            
            var obj:Object = __get_video_size_object();
            
            if (den == 0) {
                den = obj.height;
            }
            if (den == -1) {
                den = this.user_h;
            }
            
            if (num == 0) {
                num = obj.width;
            }
            if (num == -1) {
                num = this.user_w;
            }
            
            __update_video_size(num, den, this.user_w, this.user_h, this.user_w, this.user_h);
        }
        

        private function __update_video_size(_num:int, _den:int, _w:int, _h:int, _sw:int, _sh:int):void {
            if (!this.media_video || _den <= 0 || _num <= 0) {
                return;
            }
            var _height:int = _w * _den / _num;
            if (_height <= _h) {
                this.media_video.width = _w;
                this.media_video.height = _height;
            } else {
                // height overflow, calc the width by DAR
                var _width:int = _h * _num / _den;
                
                this.media_video.width = _width;
                this.media_video.height = _h;
            }
            this.media_video.x = (_sw - this.media_video.width) / 2;
            this.media_video.y = (_sh - this.media_video.height) / 2;
            
            __draw_black_background(_sw, _sh);
        }
        
        private function __draw_black_background(_width:int, _height:int):void {
            this.graphics.beginFill(0x00, 1.0);
            this.graphics.drawRect(0, 0, _width, _height);
            this.graphics.endFill();
            
            this.control_fs_mask.graphics.beginFill(0xff0000, 0);
            this.control_fs_mask.graphics.drawRect(0, 0, _width, _height);
            this.control_fs_mask.graphics.endFill();
        }
		private function log(msg:String):void {
			msg = "[" + new Date() +"][srs-player][" + js_id + "] " + msg;
			
			trace(msg);
			
			ExternalInterface.call("console.log", msg);
		}
		
    }
}
