#!/usr/bin/env ruby

require "fileutils"
require "open-uri"

ROOT = File.expand_path("..", __dir__)
DESTINATION = File.join(ROOT, "assets", "hatena", "images")

EXTENSIONS = {
  "j" => "jpg",
  "p" => "png",
  "g" => "gif"
}.freeze

def source_files
  Dir.glob(File.join(ROOT, "**", "*.{md,md.txt}"), File::FNM_EXTGLOB).reject do |path|
    relative = path.delete_prefix(ROOT + "/")
    relative.start_with?("_posts/", "_site/", "vendor/", ".git/")
  end
end

def fotolife_url(user, image_id, kind)
  extension = EXTENSIONS.fetch(kind)
  date = image_id[0, 8]
  initial = user[0]
  "https://cdn-ak.f.st-hatena.com/images/fotolife/#{initial}/#{user}/#{date}/#{image_id}.#{extension}"
end

def destination_path(user, image_id, kind)
  extension = EXTENSIONS.fetch(kind)
  File.join(DESTINATION, user, image_id[0, 8], "#{image_id}.#{extension}")
end

tokens = source_files.flat_map do |path|
  File.read(path).scan(/\[?f:id:([^:\]]+):(\d{14})([a-z]):(?:image|plain)(?::[^\]]+)*\]?/)
end.uniq

downloaded = 0
skipped = 0
failed = []

tokens.each do |user, image_id, kind|
  unless EXTENSIONS.key?(kind)
    failed << [user, image_id, kind, "unsupported image kind"]
    next
  end

  output_path = destination_path(user, image_id, kind)
  if File.exist?(output_path) && File.size?(output_path)
    skipped += 1
    next
  end

  FileUtils.mkdir_p(File.dirname(output_path))
  url = fotolife_url(user, image_id, kind)

  URI.open(url, "User-Agent" => "Mozilla/5.0") do |input|
    File.binwrite(output_path, input.read)
  end
  downloaded += 1
rescue StandardError => error
  failed << [user, image_id, kind, error.message]
end

puts "Downloaded #{downloaded} images into #{DESTINATION.delete_prefix(ROOT + "/")}."
puts "Skipped #{skipped} existing images."

if failed.any?
  warn "Failed #{failed.size} images:"
  failed.each do |user, image_id, kind, message|
    warn "- f:id:#{user}:#{image_id}#{kind}: #{message}"
  end
  exit 1
end