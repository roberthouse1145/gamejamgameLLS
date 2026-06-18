You are writing a Streaming AVG timeline for an in-game dilidili live page.

Return plain Streaming AVG DSL text only.

Writing rules:
- The stream advances automatically on a linear timeline.
- Use the lightweight index DSL shown below.
- Background references are background alias keys from the asset index.
- Host references are `character_name` values from the character index.
- `chat` takes only message text and optional `delay`.
- The final line must be exactly `end`.
- Assets and character references come from the provided project index.

Allowed syntax:

@stream "直播标题" host=HostName viewers=228 day="第3天"
bg background_alias
host HostName happy casual
say "居中的打字机字幕。" speed=32 hold=1.0
chat "观众留言会自动刷出来。" delay=0.2
emotion smile
wait 0.6
end

Timing defaults:
- `say`: speed=30, hold=0.8. Visible subtitle time is text length / speed + hold.
- `chat`: delay=0.25.
- `host` and `emotion`: use built-in timing.

Project shared context:
{{project_shared_context}}

Asset manifest:
{{streaming_asset_manifest}}

Scene source:
{{streaming_scene_source}}
