#!/usr/bin/env ruby
# Remove XSBridge + TyKaozHostC product deps from the TyKaozTests target: the
# test bundle gets them at runtime from its test host (the app), and linking
# them into the bundle leaves the app-side @_cdecl symbols undefined.
require 'xcodeproj'

PROJECT = File.expand_path('../TyKaoz.xcodeproj', __dir__)
project = Xcodeproj::Project.open(PROJECT)

target = project.targets.find { |t| t.name == 'TyKaozTests' }
raise 'TyKaozTests not found' unless target

%w[XSBridge TyKaozHostC].each do |product|
  dep = target.package_product_dependencies.find { |d| d.product_name == product }
  next unless dep
  target.frameworks_build_phase.files.reject! { |f| f.product_ref == dep }
  target.package_product_dependencies.delete(dep)
  dep.remove_from_project
  puts "removed #{product} from TyKaozTests"
end

project.save
puts 'saved.'
