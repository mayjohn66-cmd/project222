class_name OpeningRoadNoise
extends Node
## 프롤로그 소리: 파일 없이 만든 잔잔한 도로 소음(`city`)과 숲 바람(`wind`). `silence()`는 소리를 뚝 끊는다.
## 소리 장치가 없거나 꺼져 있으면(자동 검사·서버) 아무 일도 하지 않는다.

const MIX_RATE := 22050.0
const BUFFER_SECONDS := 0.4
const VOLUME_DB := -16.0
const CITY_BASE := 0.10          # 끊임없이 깔리는 소음 크기
const CITY_SWELL := 0.12         # 차가 지나갈 때의 부풀림
const WIND_LEVEL := 0.07
const CRASH_SECONDS := 1.3
const BEEP_HZ := 1500.0
const BEEP_SECONDS := 0.14
const BEEP_LEVEL := 0.3

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _mode: String = "off"
var _level: float = 0.0           # 지금 크기(0이면 무음)
var _target: float = 0.0
var _brown: float = 0.0
var _filter: float = 0.0
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()
var _fade_seconds: float = 0.6
var _crash: float = 0.0           # 쿵·와장창 소리 남은 세기(1→0)
var _beep_left: float = 0.0       # 계산대 삑 소리 남은 시간
var _beep_phase: float = 0.0


func _ready() -> void:
	_rng.seed = 7

	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = BUFFER_SECONDS
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func play(mode: String) -> void:
	_mode = mode
	_target = 1.0 if mode != "off" else 0.0


# 소리를 즉시 끊는다(말 그대로 '뚝').
func silence() -> void:
	_mode = "off"
	_target = 0.0
	_level = 0.0


# 지금 소리 크기를 level(0~1)로 seconds 동안 바꾼다(졸음에 소리가 멀어지는 느낌).
func set_level(level: float, seconds: float) -> void:
	_target = clampf(level, 0.0, 1.0)
	_fade_seconds = maxf(seconds, 0.05)


# 계산대 "삑" 소리
func beep() -> void:
	_beep_left = BEEP_SECONDS


# 가게가 통째로 쿵 하고 부서지는 소리(다른 소리가 꺼져 있어도 난다)
func crash() -> void:
	_crash = 1.0


func fade_out(seconds: float) -> void:
	_target = 0.0
	_fade_seconds = maxf(seconds, 0.05)


func _process(delta: float) -> void:
	if _playback == null:
		return

	_clock += delta
	var step: float = delta / (_fade_seconds if _target < _level else 0.8)
	_level = move_toward(_level, _target, step)
	var frames: int = _playback.get_frames_available()

	for i in range(frames):
		var white: float = _rng.randf_range(-1.0, 1.0)
		_brown = clampf(_brown * 0.985 + white * 0.06, -1.0, 1.0)
		var sample: float = 0.0

		if _mode == "city":
			var swell: float = maxf(0.0, sin(_clock * 0.9 + sin(_clock * 0.37) * 1.5))
			sample = _brown * (CITY_BASE + CITY_SWELL * swell * swell) * 2.2
		elif _mode == "wind":
			_filter = lerpf(_filter, white, 0.18)
			var gust: float = 0.55 + 0.45 * sin(_clock * 0.5 + sin(_clock * 0.21) * 2.0)
			sample = (_brown * 0.5 + _filter * 0.5) * WIND_LEVEL * gust * 2.0

		sample *= _level

		if _crash > 0.0:
			sample += (white * 0.8 + _brown * 1.3) * _crash * _crash * 0.7
			_crash = maxf(0.0, _crash - 1.0 / (MIX_RATE * CRASH_SECONDS))

		if _beep_left > 0.0:
			_beep_phase += TAU * BEEP_HZ / MIX_RATE
			sample += sin(_beep_phase) * BEEP_LEVEL
			_beep_left -= 1.0 / MIX_RATE

		_playback.push_frame(Vector2(sample, sample))
