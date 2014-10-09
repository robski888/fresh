require 'spec_helper'

describe 'fresh' do
  describe 'local shell files' do
    it 'builds' do
      add_to_file freshrc_path, 'fresh aliases/git'
      add_to_file freshrc_path, 'fresh aliases/ruby'

      add_to_file [fresh_local_path, 'aliases', 'git'], "alias gs='git status'"
      add_to_file [fresh_local_path, 'aliases', 'git'], "alias gl='git log'"
      add_to_file [fresh_local_path, 'aliases', 'ruby'], "alias rake='bundle exec rake'"

      run_fresh

      expect_shell_sh_to eq <<-EOF.strip_heredoc
        # fresh: aliases/git

        alias gs='git status'
        alias gl='git log'

        # fresh: aliases/ruby

        alias rake='bundle exec rake'
      EOF
    end

    it 'builds with spaces' do
      add_to_file freshrc_path, "fresh 'aliases/foo bar'"

      add_to_file [fresh_local_path, 'aliases', 'foo bar'], 'SPACE'
      add_to_file [fresh_local_path, 'aliases', 'foo'], 'foo'
      add_to_file [fresh_local_path, 'aliases', 'bar'], 'bar'

      run_fresh

      expect_shell_sh_to eq <<-EOF.strip_heredoc
        # fresh: aliases/foo bar

        SPACE
      EOF
    end

    it 'builds with globbing' do
      add_to_file freshrc_path, "fresh 'aliases/file*'"

      add_to_file [fresh_local_path, 'aliases', 'file1'], 'file1'
      add_to_file [fresh_local_path, 'aliases', 'file2'], 'file2'
      add_to_file [fresh_local_path, 'aliases', 'other'], 'other'

      run_fresh

      expect_shell_sh_to eq <<-EOF.strip_heredoc
        # fresh: aliases/file1

        file1

        # fresh: aliases/file2

        file2
      EOF
    end

    it 'creates empty output with no freshrc file' do
      expect(File.exists?(shell_sh_path)).to be false

      run_fresh

      expect(File.exists?(shell_sh_path)).to be true
      expect_shell_sh_to be_default
    end

    it 'builds local shell files with --ignore-missing' do
      add_to_file freshrc_path, 'fresh aliases/haskell --ignore-missing'
      FileUtils.mkdir_p fresh_local_path

      run_fresh

      expect_shell_sh_to be_default
    end

    it 'errors with missing local file' do
      add_to_file freshrc_path, 'fresh foo'
      FileUtils.mkdir_p fresh_local_path
      FileUtils.touch File.join(fresh_local_path, 'bar')

      run_fresh stderr: <<-EOF.strip_heredoc
        #{ERROR_PREFIX} Could not find "foo" source file.
        #{freshrc_path}:1: fresh foo

        You may need to run `fresh update` if you're adding a new line,
        or the file you're referencing may have moved or been deleted.
      EOF
    end

    it 'preserves existing compiled files when failing' do
      add_to_file shell_sh_path, 'existing shell.sh'

      add_to_file freshrc_path, 'invalid'
      run_fresh stderr: "#{freshrc_path}: line 1: invalid: command not found\n"

      expect(File.read(shell_sh_path)).to eq "existing shell.sh\n"
    end
  end

  describe 'remote files' do
    describe 'cloning' do
      it 'clones GitHub repos' do
        add_to_file freshrc_path, 'fresh repo/name file'
        stub_git

        run_fresh

        expect(git_log).to eq <<-EOF.strip_heredoc
          cd #{Dir.pwd}
          git clone https://github.com/repo/name #{sandbox_path}/fresh/source/repo/name
        EOF
        expect(
          File.read(File.join(sandbox_path, 'fresh', 'source', 'repo', 'name', 'file'))
        ).to eq "test data\n"
      end

      it 'clones other repos' do
        add_to_file freshrc_path, <<-EOF
          fresh git://example.com/one/two.git file
          fresh http://example.com/foo file
          fresh https://example.com/bar file
          fresh git@test.example.com:baz.git file
        EOF
        stub_git

        run_fresh

        expect(git_log).to eq <<-EOF.strip_heredoc
          cd #{Dir.pwd}
          git clone git://example.com/one/two.git #{sandbox_path}/fresh/source/example.com/one-two
          cd #{Dir.pwd}
          git clone http://example.com/foo #{sandbox_path}/fresh/source/example.com/foo
          cd #{Dir.pwd}
          git clone https://example.com/bar #{sandbox_path}/fresh/source/example.com/bar
          cd #{Dir.pwd}
          git clone git@test.example.com:baz.git #{sandbox_path}/fresh/source/test.example.com/baz
        EOF
      end

      it 'clones github repos with full urls' do
        add_to_file freshrc_path, <<-EOF
          fresh git@github.com:ssh/test.git file
          fresh git://github.com/git/test.git file
          fresh http://github.com/http/test file
          fresh https://github.com/https/test file
        EOF
        stub_git

        run_fresh

        expect(git_log).to eq <<-EOF.strip_heredoc
          cd #{Dir.pwd}
          git clone git@github.com:ssh/test.git #{sandbox_path}/fresh/source/ssh/test
          cd #{Dir.pwd}
          git clone git://github.com/git/test.git #{sandbox_path}/fresh/source/git/test
          cd #{Dir.pwd}
          git clone http://github.com/http/test #{sandbox_path}/fresh/source/http/test
          cd #{Dir.pwd}
          git clone https://github.com/https/test #{sandbox_path}/fresh/source/https/test
        EOF
      end

      it 'does not clone existing repos' do
        add_to_file freshrc_path, 'fresh repo/name file'
        touch [fresh_path, 'source/repo/name/file']
        stub_git

        run_fresh

        expect(File.exists?(git_log_path)).to be false
      end
    end

    describe 'building shell files' do
      it 'builds shell files from cloned github repos' do
        add_to_file freshrc_path, 'fresh repo/name file'
        add_to_file [fresh_path, 'source/repo/name/file'], 'remote content'

        run_fresh

        expect_shell_sh_to eq <<-EOF.strip_heredoc
          # fresh: repo/name file

          remote content
        EOF
      end

      it 'builds shell files from cloned other repos' do
        add_to_file freshrc_path, 'fresh git://example.com/foobar.git file'
        add_to_file [fresh_path, 'source/example.com/foobar/file'], 'remote content'

        run_fresh

        expect_shell_sh_to eq <<-EOF.strip_heredoc
          # fresh: git://example.com/foobar.git file

          remote content
        EOF
      end
    end

    it 'warns if using a remote source that is your local dotfiles' do
      add_to_file freshrc_path, <<-EOF.strip_heredoc
        fresh repo/name file1
        fresh repo/name file2
      EOF
      FileUtils.mkdir_p File.join(fresh_local_path, '.git')
      FileUtils.mkdir_p File.join(fresh_path, 'source/repo/name/.git')
      [1, 2].each do |n|
        FileUtils.touch File.join(fresh_path, 'source/repo/name', "file#{n}")
      end
      stub_git

      run_fresh stdout: <<-EOF.strip_heredoc
        #{NOTE_PREFIX} You seem to be sourcing your local files remotely.
        #{freshrc_path}:1: fresh repo/name file1

        You can remove "repo/name" when sourcing from your local dotfiles repo (#{fresh_local_path}).
        Use \`fresh file\` instead of \`fresh repo/name file\`.

        To disable this warning, add \`FRESH_NO_LOCAL_CHECK=true\` in your freshrc file.

        #{FRESH_SUCCESS_LINE}
      EOF

      expect(git_log).to eq <<-EOF.strip_heredoc
        cd #{fresh_local_path}
        git rev-parse --abbrev-ref --symbolic-full-name @{u}
        cd #{fresh_local_path}
        git config --get remote.my-remote-name.url
      EOF
    end

    it 'does not fail if local dotfiles does not have a remote' do
      add_to_file freshrc_path, 'fresh repo/name file'
      FileUtils.mkdir_p File.join(fresh_path, 'source/repo/name/.git')
      FileUtils.touch File.join(fresh_path, 'source/repo/name/file')

      FileUtils.mkdir_p fresh_local_path
      silence(:stdout) do
        expect(system 'git', 'init', fresh_local_path).to be true
      end

      run_fresh
    end

    describe 'using --ref' do
      it 'builds' do
        add_to_file freshrc_path, <<-EOF.strip_heredoc
          fresh repo/name 'aliases/*' --ref=abc1237
          fresh repo/name ackrc --file --ref=1234567
          fresh repo/name sedmv --bin --ref=abcdefg
        EOF
        # test with only one of aliases/* existing at HEAD
        touch [fresh_path, 'source/repo/name/aliases/git.sh']
        stub_git

        run_fresh

        source_repo_name_dir_path = File.join(fresh_path, 'source/repo/name')
        expect(git_log).to eq <<-EOF.strip_heredoc
          cd #{source_repo_name_dir_path}
          git show abc1237:aliases/.fresh-order
          cd #{source_repo_name_dir_path}
          git ls-tree -r --name-only abc1237
          cd #{source_repo_name_dir_path}
          git show abc1237:aliases/git.sh
          cd #{source_repo_name_dir_path}
          git show abc1237:aliases/ruby.sh
          cd #{source_repo_name_dir_path}
          git ls-tree -r --name-only 1234567
          cd #{source_repo_name_dir_path}
          git show 1234567:ackrc
          cd #{source_repo_name_dir_path}
          git ls-tree -r --name-only abcdefg
          cd #{source_repo_name_dir_path}
          git show abcdefg:sedmv
        EOF

        expect_shell_sh_to eq <<-EOF.strip_heredoc
          # fresh: repo/name aliases/git.sh @ abc1237

          test data for abc1237:aliases/git.sh

          # fresh: repo/name aliases/ruby.sh @ abc1237

          test data for abc1237:aliases/ruby.sh
        EOF

        expect(File.read(File.join(fresh_path, 'build/ackrc'))).
          to eq "test data for 1234567:ackrc\n"
        expect(File.read(File.join(fresh_path, 'build/bin/sedmv'))).
          to eq "test data for abcdefg:sedmv\n"
      end

      it 'errors if source file missing at ref' do
        add_to_file freshrc_path, 'fresh repo/name bad-file --ref=abc1237'
        FileUtils.mkdir_p File.join(fresh_path, 'source/repo/name')
        stub_git

        run_fresh stderr: <<-EOF.strip_heredoc
          #{ERROR_PREFIX} Could not find "bad-file" source file.
          #{freshrc_path}:1: fresh repo/name bad-file --ref=abc1237

          You may need to run `fresh update` if you're adding a new line,
          or the file you're referencing may have moved or been deleted.
          Have a look at the repo: <#{format_url 'https://github.com/repo/name'}>
        EOF

        expect(git_log).to eq <<-EOF.strip_heredoc
          cd #{fresh_path}/source/repo/name
          git ls-tree -r --name-only abc1237
        EOF
      end

      context 'with --ignore-missing' do
        it 'does not error if source file missing at ref with --ignore-missing' do
          add_to_file freshrc_path, 'fresh repo/name bad-file --ref=abc1237 --ignore-missing'
          FileUtils.mkdir_p File.join(fresh_path, 'source/repo/name')
          stub_git

          run_fresh

          expect(git_log).to eq <<-EOF.strip_heredoc
            cd #{fresh_path}/source/repo/name
            git ls-tree -r --name-only abc1237
          EOF
        end

        it 'builds files with ref and ignore missing' do
          add_to_file freshrc_path, <<-EOF.strip_heredoc
            fresh repo/name ackrc --file --ref=abc1237 --ignore-missing
            fresh repo/name missing --file --ref=abc1237 --ignore-missing
          EOF
          FileUtils.mkdir_p File.join(fresh_path, 'source/repo/name')
          stub_git

          run_fresh

          source_repo_name_dir_path = File.join(fresh_path, 'source/repo/name')
          expect(git_log).to eq <<-EOF.strip_heredoc
            cd #{source_repo_name_dir_path}
            git ls-tree -r --name-only abc1237
            cd #{source_repo_name_dir_path}
            git show abc1237:ackrc
            cd #{source_repo_name_dir_path}
            git ls-tree -r --name-only abc1237
          EOF
          expect(File.exists? File.join(fresh_path, 'build/ackrc')).to be true
          expect(File.exists? File.join(fresh_path, 'missing')).to be false
        end
      end
    end
  end

  describe 'ignoring subdirectories when globbing' do
    it 'from working tree' do
      add_to_file freshrc_path, "fresh 'recursive-test/*'"
      %w[abc/def foo bar].each do |path|
        touch File.join(fresh_local_path, 'recursive-test', path)
      end

      run_fresh

      expect(File.read(shell_sh_path).lines.grep(/^# fresh/).join).to eq <<-EOF.strip_heredoc
        # fresh: recursive-test/bar
        # fresh: recursive-test/foo
      EOF
    end

    it 'with ref' do
      add_to_file freshrc_path, "fresh repo/name 'recursive-test/*' --ref=abc1237"
      stub_git

      run_fresh

      expect(File.read(shell_sh_path).lines.grep(/^# fresh/).join).to eq <<-EOF.strip_heredoc
          # fresh: repo/name recursive-test/bar @ abc1237
          # fresh: repo/name recursive-test/foo @ abc1237
      EOF
    end
  end
end
