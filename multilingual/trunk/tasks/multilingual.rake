desc "Run the unit tests for the multilingual rails plugin"
Rake::TestTask.new "test_multilingual" do |t|
  t.pattern = "./vendor/plugins/multilingual/test/*_test.rb"
  t.verbose = true
end
