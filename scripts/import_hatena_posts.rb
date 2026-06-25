#!/usr/bin/env ruby

require "fileutils"
require "time"
require "yaml"
require "uri"

ROOT = File.expand_path("..", __dir__)
DESTINATION = File.join(ROOT, "_posts", "hatena")

def source_files
  Dir.glob(File.join(ROOT, "**", "*.{md,md.txt}"), File::FNM_EXTGLOB).reject do |path|
    relative = path.delete_prefix(ROOT + "/")
    relative.start_with?("_posts/", "_site/", "vendor/", ".git/") ||
      %w[README.md index.md archive.html categories.html pages.html tags.html].include?(relative)
  end
end

def front_matter_and_body(text)
  return [nil, text] unless text.start_with?("---\n")

  parts = text.split(/^---\s*$\n?/, 3)
  return [nil, text] unless parts.length >= 3

  [parts[1], parts[2]]
end

def metadata_from_yaml(front_matter)
  YAML.safe_load(front_matter, permitted_classes: [Date, Time], aliases: true) || {}
rescue Psych::Exception
  {}
end

def metadata_from_lines(front_matter)
  metadata = {}
  front_matter.each_line do |line|
    key, value = line.split(":", 2)
    next unless key && value

    metadata[key.strip] ||= value.strip.gsub(/\A['"]|['"]\z/, "")
  end
  metadata
end

def normalize_categories(value)
  Array(value).map(&:to_s).map(&:strip).reject(&:empty?)
end

def hatena_permalink(url)
  return nil if url.to_s.empty?

  uri = URI.parse(url)
  path = uri.path
  return nil if path.empty?

  path.end_with?("/") ? path : "#{path}/"
rescue URI::InvalidURIError
  nil
end

def fallback_slug(path)
  basename = File.basename(path).sub(/\.md(?:\.txt)?\z/, "")
  basename.gsub(/[^0-9A-Za-z_-]+/, "-").gsub(/\A-|-\z/, "")
end

def normalize_hatena_markup(body)
  body.gsub(/^>\|([^|]*)\|\n(.*?)^\|\|<\s*$/m) do
    language = Regexp.last_match(1).strip
    code = Regexp.last_match(2).sub(/\n\z/, "")
    "```#{language}\n#{code}\n```"
  end
end

def split_hatena_sections(body, default_title, default_categories, known_categories)
  sections = [{ "title" => default_title, "categories" => default_categories, "body" => "" }]

  body.each_line do |line|
    if (match = line.match(/^\[([^\]]+)\]\s+(.+)$/)) && hatena_section_heading?(match[1].strip, match[2].strip, known_categories)
      sections << {
        "title" => match[2].strip,
        "categories" => [match[1].strip],
        "body" => ""
      }
    else
      sections.last["body"] << line
    end
  end

  sections.map { |section| section.merge("body" => section["body"].lstrip) }
          .reject { |section| section["body"].strip.empty? }
end

def hatena_section_heading?(category, title, known_categories)
  return true if known_categories.include?(category)
  return false if category.match?(/[.:\\\/]/)
  return false if title.start_with?("-", "–", "—")

  category.match?(/[^\x00-\x7F]/)
end

def output_path_for(path, date, used_paths)
  slug = fallback_slug(path)
  slug = "entry" if slug.empty?
  base = File.join(DESTINATION, "#{date.strftime("%Y-%m-%d")}-#{slug}.md")
  candidate = base
  counter = 2

  while used_paths[candidate]
    candidate = base.sub(/\.md\z/, "-#{counter}.md")
    counter += 1
  end

  used_paths[candidate] = true
  candidate
end

def output_path_for_section(path, date, used_paths, section_index)
  return output_path_for(path, date, used_paths) if section_index.zero?

  slug = fallback_slug(path)
  slug = "entry" if slug.empty?
  candidate = File.join(DESTINATION, "#{date.strftime("%Y-%m-%d")}-#{slug}-#{section_index + 1}.md")

  while used_paths[candidate]
    section_index += 1
    candidate = File.join(DESTINATION, "#{date.strftime("%Y-%m-%d")}-#{slug}-#{section_index + 1}.md")
  end

  used_paths[candidate] = true
  candidate
end

def permalink_for_section(source_url, section_index)
  permalink = hatena_permalink(source_url)
  return permalink if section_index.zero? || permalink.nil?

  "#{permalink.chomp("/")}/#{section_index + 1}/"
end

dry_run = ARGV.include?("--dry-run")
FileUtils.rm_rf(DESTINATION) unless dry_run
FileUtils.mkdir_p(DESTINATION) unless dry_run

imported = 0
skipped = 0
used_paths = {}
sources = source_files
known_categories = sources.flat_map do |path|
  front_matter, = front_matter_and_body(File.read(path))
  front_matter ? normalize_categories(metadata_from_yaml(front_matter)["Category"]) : []
end.uniq

sources.each do |path|
  front_matter, body = front_matter_and_body(File.read(path))
  unless front_matter
    skipped += 1
    next
  end

  metadata = metadata_from_lines(front_matter).merge(metadata_from_yaml(front_matter))
  source_url = metadata["URL"].to_s
  date_value = metadata["Date"] || metadata["date"]

  unless source_url.include?("tkatochin.hatenablog.com") && date_value
    skipped += 1
    next
  end

  date = Time.parse(date_value.to_s)
  title = metadata["Title"].to_s.strip.empty? ? "■" : metadata["Title"].to_s.strip
  categories = normalize_categories(metadata["Category"] || metadata["category"])
  sections = split_hatena_sections(body, title, categories, known_categories)

  sections.each_with_index do |section, section_index|
    output_path = output_path_for_section(path, date, used_paths, section_index)
    post_data = {
      "layout" => "post",
      "title" => section["title"],
      "date" => (date + section_index).iso8601,
      "categories" => section["categories"],
      "source_url" => source_url,
      "edit_url" => metadata["EditURL"].to_s,
      "permalink" => permalink_for_section(source_url, section_index)
    }.reject { |_, value| value.nil? || value == [] || value == "" }

    unless dry_run
      File.write(output_path, "#{post_data.to_yaml}---\n{% include JB/setup %}\n\n#{normalize_hatena_markup(section["body"])}")
    end
    imported += 1
  end
end

puts "Imported #{imported} posts into #{DESTINATION.delete_prefix(ROOT + "/")}."
puts "Skipped #{skipped} files."