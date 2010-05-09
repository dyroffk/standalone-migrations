describe 'Standalone migrations' do
  def write(file, content)
    raise "cannot write nil" unless file
    file = tmp_file(file)
    folder = File.dirname(file)
    `mkdir -p #{folder}` unless File.exist?(folder)
    File.open(file,'w'){|f| f.write content}
  end

  def read(file)
    File.read(tmp_file(file))
  end

  def migration(name)
    m = `cd spec/tmp/db/migrations && ls`.split("\n").detect{|m| m =~ name}
    m ? "db/migrations/#{m}" : m
  end

  def tmp_file(file)
    "spec/tmp/#{file}"
  end

  def run(cmd)
    `cd spec/tmp && #{cmd} 2>&1 && echo SUCCESS`
  end

  def make_migration(name)
    migration = run("rake db:new_migration name=#{name}").match(%r{db/migrations/\d+.*.rb})[0]
    content = read(migration)
    content.sub!(/def self.down.*?\send/m, "def self.down;puts 'DOWN-#{name}';end")
    content.sub!(/def self.up.*?\send/m, "def self.up;puts 'UP-#{name}';end")
    write(migration, content)
    migration.match(/\d{14}/)[0]
  end

  before do
    `rm -rf spec/tmp` if File.exist?('spec/tmp')
    `mkdir spec/tmp`
    write 'Rakefile', <<-TXT
      $LOAD_PATH.unshift '#{File.expand_path('lib')}'
      begin
        require 'tasks/standalone_migrations'
        MigratorTasks.new
      rescue LoadError => e
        puts "gem install standalone_migrations to get db:migrate:* tasks! (Error: \#{e})"
      end
    TXT
    write 'db/config.yml', <<-TXT
      development:
        adapter: sqlite3
        database: db/development.sql
      test:
        adapter: sqlite3
        database: db/test.sql
    TXT
  end

  describe 'db:new_migration' do
    it "fails if i do not add a name" do
      run("rake db:new_migration").should_not =~ /SUCCESS/
    end

    it "generates a new migration with this name and timestamp" do
      run("rake db:new_migration name=test_abc").should =~ %r{Created migration .*spec/tmp/db/migrations/\d+_test_abc\.rb}
      run("ls db/migrations").should =~ /^\d+_test_abc.rb$/
    end
  end

  describe 'db:migrate' do
    it "does nothing when no migrations are present" do
      run("rake db:migrate").should =~ /SUCCESS/
    end

    it "migrates if i add a migration" do
      run("rake db:new_migration name=xxx")
      result = run("rake db:migrate")
      result.should =~ /SUCCESS/
      result.should =~ /Migrating to Xxx \(#{Time.now.year}/
    end
    
    context ""
  end

  describe 'db:migrate:down' do
    it "migrates down" do
      make_migration('xxx')
      sleep 1
      version = make_migration('yyy')
      run 'rake db:migrate'

      result = run("rake db:migrate:down VERSION=#{version}")
      result.should =~ /SUCCESS/
      result.should_not =~ /DOWN-xxx/
      result.should =~ /DOWN-yyy/
    end

    it "fails without version" do
      make_migration('yyy')
      result = run("rake db:migrate:down")
      result.should_not =~ /SUCCESS/
    end
  end

  describe 'db:migrate:up' do
    it "migrates up" do
      make_migration('xxx')
      run 'rake db:migrate'
      sleep 1
      version = make_migration('yyy')
      result = run("rake db:migrate:up VERSION=#{version}")
      result.should =~ /SUCCESS/
      result.should_not =~ /UP-xxx/
      result.should =~ /UP-yyy/
    end

    it "fails without version" do
      make_migration('yyy')
      result = run("rake db:migrate:up")
      result.should_not =~ /SUCCESS/
    end
  end

  describe 'schema:dump' do
    it "dumps the schema" do
      result = run('rake db:schema:dump')
      result.should =~ /SUCCESS/
      read('db/schema.rb').should =~ /ActiveRecord/
    end
  end

  describe 'db:schema:load' do
    it "loads the schema" do
      run('rake db:schema:dump')
      schema = "db/schema.rb"
      write(schema, read(schema)+"\nputs 'LOADEDDD'")
      result = run('rake db:schema:load')
      result.should =~ /SUCCESS/
      result.should =~ /LOADEDDD/
    end
  end

  describe 'db:abort_if_pending_migrations' do
    it "passes when no migrations are pending" do
      run("rake db:abort_if_pending_migrations").should_not =~ /try again/
    end

    it "fails when migrations are pending" do
      make_migration('yyy')
      result = run("rake db:abort_if_pending_migrations")
      result.should =~ /try again/
      result.should =~ /1 pending migration/
    end
  end

  describe 'db:test:load' do
    it 'loads' do
      write("db/schema.rb", "puts 'LOADEDDD'")
      run("rake db:test:load").should =~ /LOADEDDD.*SUCCESS/m
    end

    it "fails without schema" do
      run("rake db:test:load").should =~ /no such file to load/
    end
  end

  describe 'db:test:purge' do
    it "runs" do
      run('rake db:test:purge').should =~ /SUCCESS/
    end
  end
end