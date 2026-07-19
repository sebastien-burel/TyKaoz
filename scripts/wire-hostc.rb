#!/usr/bin/env ruby
# Wire the TyKaozHostC local package + the XSBridge product into TyKaoz.xcodeproj.
# Idempotent: safe to re-run. Requires the `xcodeproj` gem.
require 'xcodeproj'

PROJECT = File.expand_path('../TyKaoz.xcodeproj', __dir__)
project = Xcodeproj::Project.open(PROJECT)

def local_ref(project, rel_path)
  project.root_object.package_references.find do |r|
    r.isa == 'XCLocalSwiftPackageReference' && r.relative_path == rel_path
  end
end

def ensure_local_ref(project, rel_path)
  existing = local_ref(project, rel_path)
  return existing if existing
  ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  ref.relative_path = rel_path
  project.root_object.package_references << ref
  ref
end

def ensure_product(target, project, package_ref, product_name)
  dep = target.package_product_dependencies.find { |d| d.product_name == product_name }
  unless dep
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = product_name
    dep.package = package_ref if package_ref
    target.package_product_dependencies << dep
  end
  phase = target.frameworks_build_phase
  unless phase.files.any? { |f| f.product_ref == dep }
    bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    bf.product_ref = dep
    phase.files << bf
  end
  dep
end

xsbridgekit_ref = local_ref(project, '../XSBridgeKit')
raise 'XSBridgeKit local package reference not found' unless xsbridgekit_ref
hostc_ref = ensure_local_ref(project, '../TyKaozHostC')

%w[TyKaoz TyKaozTests].each do |name|
  target = project.targets.find { |t| t.name == name }
  raise "target #{name} not found" unless target
  ensure_product(target, project, xsbridgekit_ref, 'XSBridge')
  ensure_product(target, project, hostc_ref, 'TyKaozHostC')
  puts "wired #{name}: XSBridge + TyKaozHostC"
end

project.save
puts 'saved.'
