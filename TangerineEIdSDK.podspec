

Pod::Spec.new do |spec|

  spec.name         = "TangerineEIdSDK"
  spec.version      = "1.0.0"
  spec.summary      = "TangerineEld SDK allow you to scan all nearby devices, connect and receive ELD related trip data."
  spec.description  = "This framework allows you to scan ELD devices in vicinity, connect and receive ELD related trip data.It is compatible with Tangerine sense hardware."
  spec.homepage     = "https://github.com/Tangerine-AI"
  spec.license      = "MIT"
  spec.author             = { "Suraj" => "suraj.singh@tangerine.ai" }
  spec.platform     = :ios, "12.2"
  spec.source       = { :git => "https://github.com/Tangerine-AI/TangerineEIdSDK.git", :tag => "1.0.0" }
  spec.framework = "TangerineEld"
  spec.vendored_frameworks = 'TangerineEld.framework'
  spec.swift_version = "5.0"
end



