class LeanTitleVersionImport
  include SidekiqWorkflow
  sidekiq_options retry: 0
  workflow do
    description do |title_version_id, options|
      "LeanTitleVersionImport: tv=#{title_version_id} #{options}"
    end

    step :processor do |title_version_id, options|
      step_jobs do
        SampleJob.set(queue: %w(high default low).sample).perform_async(title_version_id, options.merge("processor" => 1))
      end
    end

    step :xml_generation do |title_version_id, options|
      step_jobs do
        SampleJob.set(queue: %w(high default low).sample).perform_async(title_version_id, options.merge("xml_generation" => 1))
      end
    end

    success do |title_version_id, options|
      puts "Done with tv=#{title_version_id}"

      parent_jobs do
        if options["version"] <= 3
          LeanTitleVersionImport.start(title_version_id, options.merge("version" => options["version"] + 1))
        end
      end
    end
  end
end

class Workflow::ParallelTitleVersionImport
  include SidekiqWorkflow
	sidekiq_options retry: 0

	workflow do
    description do |titles|
      "Parallel Title import for titles #{titles.to_sentence}"
    end

    step :preprocess_all do |titles|
      step_jobs do
        titles.each{|x| SampleJob.set(queue: %w(high default low).sample).perform_async(x, {"preprocess" => 1})}
      end
    end

    step :process_in_order do |titles|
      step_jobs do
        titles.each{|x| LeanTitleVersionImport.start(x, {"version" => 1})}
      end
    end

    success do |titles|
      puts "ParallelTitleVersionImport complete for all #{titles}"
    end
  end
end

