# move this class into podutils_helper
require 'fastlane_core/ui/ui'

module Fastlane
	UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")
 	module Helper

		class PodVersion

			# comparison result constants
			VERSION_GREATER = -1
			VERSION_SAME = 0
			VERSION_LOWER = 1

			attr_accessor :major, :minor, :build

			# initialize with version numbers
			# - major major version number
			# - minor minor version number
			# - build build version number
			def initialize(major, minor, build)
				@major = major
				@minor = minor
				@build = build
			end

			# returns the canonical string for tagging and podspec versioning
			def versionString()
				return "#{major}.#{minor}.#{build}"
			end

			# update version info
			# - major major version number
			# - minor minor version number
			# - build build version number
			def update(major, minor, build)
				@major = major
				@minor = minor
				@build = build
			end

			# bump major by 1, minor and build are reset to 0
			def bumpMajor()
				@major += 1
				@minor = 0
				@build = 0
			end

			# bump minor by 1, build is reset to 0
			def bumpMinor()
				@minor += 1
				@build = 0
			end

			# bump build by 1
			def bumpBuild()
				@build += 1
			end

			# compare versions
			# - rhs rhs version to compare  
			# return -1 if lhs is lower, +1 if greater, 0 if equal
			def compare(rhs)

				if (@major > rhs.major) 
					return VERSION_LOWER
				elsif (@major < rhs.major)
					return VERSION_GREATER
				elsif (@minor > rhs.minor) 
					return VERSION_LOWER
				elsif (@minor < rhs.minor) 
					return VERSION_GREATER
				elsif (@build > rhs.build) 
					return VERSION_LOWER
				elsif (@build < rhs.build) 
					return VERSION_GREATER
				else
					return VERSION_SAME
				end

			end

		end

		# stores the old and new bumped version podspec
		# and the new version info (major, minor, build)
		class PodSpecVersionInfo 

			attr_accessor :podversion, :update_spec, :original_spec

			# initialize with version info object
			# - :podversion the intended new version
			# - :update_spec  the podspec with updated version
			# - :original_spec the podspec with the original version
			def initialize(podversion, update_spec, original_spec)
				@podversion = podversion
				@update_spec = update_spec
				@original_spec = original_spec
			end

			def versionString()
				return @podversion.versionString()
			end

		end

		# encapsulates the functionality needed to push a new pod version
		# with the ability to roll back any changes made in case of error
		class PodutilsHelper

			# bump method constants
			BUMP_BUILD = 0x0  # bump build only,  	e.g. 1.3.6 => 1.3.7
			BUMP_MINOR = 0x1  # bump minor version, e.g. 1.3.6 => 1.4.6
			BUMP_MAJOR = 0x2  # bump major version, e.g. 1.3.6 => 2.0.0

			attr_accessor :podspec, :podrepo, :verbose, :bumpMethod, :skipLibLint, :noClean

			##################### public

			# initialize class
			# - :podspec the podspec name. for example: 'ybs-core.podspec'
			# - :podrepo the pod repo name. for example: 'ybs-core'
			# - :verbose set to true for verbose logging.  default is false
			# - :bumpMethod whether to bump major, minor or build.  default is BUMP_BUILD
			# - :skipLibLint set to true to skip 'pod lib lint'.  default is false
			# - :noClean set to true to not clean up or rollback on error.  default is false
			# - :libLintOnly set to true to only 'pod lib lint'.  default is false
			# 	(note if you set skipLibLint and libLintOnly, release_pod will do nothing.)
			# - throws StandardError if bump method is invalid. 
			def initialize(params = {})

				@podspec = params.fetch(:podspec)
				@libLintOnly = params.fetch(:libLintOnly)
				@verbose = params.fetch(:verbose)


				if (@podspec == nil) 
					raise StandardError.new("no podspec specified")
				end

				if (!@libLintOnly)
					@podrepo = params.fetch(:podrepo)
					@bumpMethod = params.fetch(:bumpMethod)
					@skipLibLint = params.fetch(:skipLibLint)
					@noClean = params.fetch(:noClean)				
				
					if (@podrepo == nil)
						raise StandardError.new("no pod repo specified.")
					end

					if (@bumpMethod != BUMP_BUILD && @bumpMethod != BUMP_MINOR && @bumpMethod != BUMP_MAJOR)
						raise StandardError.new("invalid bumpMethod #{@bumpMethod}")
					end
					verbose_message("initialize...\n\tpodspec = #{@podspec}\n\tpodrepo = #{@podrepo}\n\tbumpMethod = #{bump_method_to_string()}")
				else
					verbose_message("initialize...\n\tpodspec = #{@podspec}\n\tlibLintOnly")
				end
				
			end

			def lint()

				begin

					check_podspec_exists()

					UI.message("linting pod locally") if (@verbose)
					lint_pod_lib()
				
				rescue Exception => error

					UI.message("pod lint failed with #{error}")
					raise error

				end


			end

			# main entry point into the release pod functionality
			# this function will perform following steps:
			#
			# 1. extract exsiting version from podspec
			# 2. bump version by specified bump method
			# 3. validate bumped version against existing tags
			# 4. update the podspec
			# 5. lint the pod locally
			# 6. push to master, create new tag and push tag
			# 7. push the pod to the repo
			# 8. tidy up any intermediate files (these are gitignored)
			#
			# if at any step the process errors, the command will revert
			# any changes by doing the following:
			#
			# 1. restore podspec to previous version
			# 2. push change to master
			# 3. delete the new tag both locally and remotely
			# 4. tidy up any intermediate files (these are git-ignored)
			#
			def run()

				# start the exception handling block
				begin

					check_podspec_exists()

					# lib pod library - if it fails bail immediately
					if (@skipLibLint)
						UI.message("skipping pod lib lint") if (@verbose)
					else
						UI.message("linting pod locally") if (@verbose)
						lint_pod_lib()
					end

					if (@libLintOnly)
						UI.message("lib linted ok")
						return
					end

					# parse podspec, returning bumped version and text for
					# both the original, and new bumped version podspec
					info = parse_podspec()

					if (@verbose) 
						UI.message("creating pod:")
						UI.message("\tpodspec = #{@podspec}")
						UI.message("\tpodrepo = #{@podrepo}")
						UI.message("\tversion = #{info.versionString()}")
						UI.message("\tskipLibLint = #{@skipLibLint}")
						UI.message("\tnoClean = #{@noClean}")
						UI.message("\tlibLintOnly = #{@libLintOnly}")
					end

					# check new version is greater than any existing tag
					verbose_message("checking version bump ok")
					semantic_validate(info.podversion)

					# save the original podspec to a temporary filename
					oldfname = old_filename()
					
					verbose_message("saving original podspec to #{oldfname}")
					save_podspec(oldfname, info.original_spec)

					# save the bumped version text to the podspec
					verbose_message("saving new podspec to #{@podspec}")

					save_podspec(@podspec, info.update_spec)

					# commit changes
					verbose_message("commit podspec revision: #{info.versionString()}")

					git_commit_push("commit podspec revision: #{info.versionString()}")

					# tag changes based on bumped version
					verbose_message("creating new tag: #{info.versionString()}")

					git_tag(info.versionString())

					# try to public the podspec, it'll throw if something goes wrong
					publish_pod_lib()

					if (@noClean) 
						verbose_message("noClean set.  Skipping clean up step")
					else
						verbose_message("tidying up old files")
						delete_oldpodspec_file(@podspec)
					end

					UI.message("pod version #{info.versionString()} published OK")

				rescue Exception => error

					UI.message("pod create failed with #{error}")

					if (@noClean) 
						verbose_message("noClean set.  Skipping clean up")
					else
						verbose_message("rolling back changes")
						rollback_changes(@podspec, info)
					end

					# rethrow the error, so fastlane fails
					raise error

				end

			end

			##################### private

			private

			def check_podspec_exists()
				if (!File.exists?(@podspec))
					raise StandardError.new("Error: podspec `#{@podspec}` not found")
				end
			end

			def bump_method_to_string()

				if (@bumpMethod == BUMP_BUILD)
					return "BUMP_BUILD"
				elsif (@bumpMethod == BUMP_MINOR)
					return "BUMP_MINOR"
				elsif (@bumpMethod == BUMP_MAJOR)
					return "BUMP_MAJOR"
				else
					return "INVALID"
				end
					
			end

			def shell_command(command)
				return Fastlane::Actions::sh(command)
			end

			# semantic compare of latest repo tag against new version
			# - newVersion the indended new version
			# - throws StandardError if new version isn't greater than latest tag
			def semantic_validate(newVersion)

				podversion = PodVersion.new(-1,-1,-1)

				taglist = shell_command("git tag").split("\n")
				taglist.each do | tag |
					matches = /(\d+)\.(\d+)\.(\d+)/.match(tag)
					if (matches.size == 4)

						if (matches[1].to_i > podversion.major) 
							podversion.update(matches[1].to_i, matches[2].to_i,matches[3].to_i)
						end

						if (matches[2].to_i > podversion.minor)
							podversion.update(podversion.major, matches[2].to_i,matches[3].to_i)
						end

						if (matches[3].to_i > podversion.build)
							podversion.update(podversion.major, podversion.minor, matches[3].to_i)
						end
					end

				end

				compareResult = podversion.compare(newVersion)

				if (compareResult != PodVersion::VERSION_GREATER)
					raise StandardError.new("pod version: #{newVersion.versionString()} " + 
											"is not greater than the latest tag #{podversion.versionString()}")
				end

			end

			# parse podspec for version info and bump by given method
			# returns PodSpecVersionInfo object if version found
			# throws StandardError if no version can be found
		  	def parse_podspec()

				newVersion = PodVersion.new(-1,-1,-1)
		  		update_spec = ""
		  		original_spec = ""

		  		File.open(@podspec).each do |line|

		  			matches = /(s\.version\s*=\s*\")(\d+)\.(\d+)\.(\d+)\"/.match(line)

		  			if (matches != nil && matches.size == 5)

						newVersion.update(matches[2].to_i, matches[3].to_i, matches[4].to_i)

						verbose_message("located podspec version = #{newVersion.versionString()}")

		  				if (@bumpMethod == BUMP_MAJOR)
		  					newVersion.bumpMajor()
		  				elsif (@bumpMethod == BUMP_MINOR)
		  					newVersion.bumpMinor()
		  				elsif (@bumpMethod == BUMP_BUILD)
		  					newVersion.bumpBuild()
		  				end

		  				verbose_message("updated podspec version = #{newVersion.versionString()}")

		  				update_spec += "#{matches[1]}#{newVersion.versionString()}\"\n"
		  				original_spec += "#{line}"

					else
						update_spec += "#{line}"
						original_spec += "#{line}"
		  			end
		  		end

		  		if (newVersion.major != -1) 
		  			return PodSpecVersionInfo.new(newVersion, update_spec, original_spec)
		  		else
		  			raise StandardError.new("parse #{@podspec} failed, version info not found")
		  			return nil
		  		end
		  	end

		  	# returns a temporary filename for original podspec
			def old_filename() 
		  		return @podspec + "_old"
		  	end

		  	# lints the pod locally
		  	def lint_pod_lib()

		  		output = shell_command("bundle exec pod lib lint #{podspec} --allow-warnings")
		  		lint_pod_validate(output)
		  	end

		  	def lint_pod_validate(output)

		  		podspecComponents = @podspec.split(".")
		  		psregex = "#{podspecComponents[0]} passed validation"
		  		output.split("\n").each do |line|
		  			if psregex.match(line)
		  				return
		  			end
		  		end
		  		StandardError.new("pod lib lint failed")
		  	end

		  	# pushes the new pod version to the repo
		  	def publish_pod_lib()
		  		verbose_message("publishing pod repo=#{@podrepo} spec=#{@podspec}")
		  		shell_command("bundle exec pod repo push #{@podrepo} #{@podspec} --allow-warnings")
		  	end

		  	# saves podspec to file
		  	# - filename file to write to
		  	# - spec spec text to write
		  	def save_podspec(filename, spec)
		  		open(filename, 'w') { |f|
		 			f.puts spec
				}
		  	end

			# commit changes and push
		  	def git_commit_push(message)
		  		shell_command("git commit -a -m #{message}")
		  		shell_command("git commit")
		  	end

		  	# git tag new version
		  	# - versionString tag string value
			def git_tag(versionString) 
				shell_command("git tag #{versionString}")
				shell_command("git push origin --tags")
			end

			# git delete tag locally and remotely
			# - versionString tag string value
			def git_tag_delete(versionString) 
				shell_command("git push --delete origin #{versionString}")
				shell_command("git tag --delete #{versionString}")
			end


			# rolls back any changes in case of error
			# - podspecFile new podspec file
			# - info new version info
			def rollback_changes(podspecFile, info)

				save_podspec(podspecFile, info.original_spec)
				oldspec = old_filename()
				File.delete(oldspec) if File.exist?(oldspec)

				git_commit_push("reverting back from #{info.versionString()}")
				git_tag_delete("#{info.versionString()}")
			end

			# cleans up the old podspec
			# - podspecFile path to original file
			def delete_oldpodspec_file(podspecFile)
				oldspec = old_filename()
				File.delete(oldspec) if File.exist?(oldspec)
			end

			# stick all the verbose messages into one call
			def verbose_message(msg)
				UI.message(msg) if (@verbose)
			end

		end
	end
end

