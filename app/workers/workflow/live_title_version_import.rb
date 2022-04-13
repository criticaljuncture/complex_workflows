class Workflow::LiveTitleVersionImport
  include SidekiqWorkflow
	sidekiq_options retry: 0

	workflow do
		description do |title_version_id, options|
			"Live Title Version Import for tv=#{title_version_id}"
		end

		step :preprocessor do |title_version_id, options|
			step_jobs do
				TitleVersionSourceXmlPreprocessor.perform_async(title_version_id, options)
			end
		end
		
		step :processor do |title_version_id, options|
			workflow_jobs do
				TitleVersionSourceXmlProcessor.set(queue: "low").perform_async(title_version_id, "workflow-level" => "baz")
			end
			parent_jobs do
				TitleVersionSourceXmlProcessor.set(queue: "low").perform_async(42, "preprocess" => "baz")      
			end
			
			step_jobs do
				TitleVersionSourceXmlProcessor.perform_async(title_version_id, options)
			end
		end

		step :indexer do |title_version_id, options|
			puts "Indexer: tv=#{title_version_id}, options=#{options}"
			step_jobs do
				TitleVersionSourceXmlProcessor.perform_async(title_version_id, {"indexer" => "true"})
			end
		end

		success do |title_version_id, options|
			sleep(1)
			puts "Workflow Success! #{title_version_id} #{options}"
			
			parent_jobs do
				self.class.start(title_version_id+1, options) if title_version_id < 3
			end
		end
  end
end