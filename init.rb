Dir.glob(File.expand_path("lib/**/*.rb")).each do |file|
  require file
end