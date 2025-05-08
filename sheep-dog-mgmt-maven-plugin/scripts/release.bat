cd ..
call mvn org.codehaus.mojo:versions-maven-plugin:update-properties -DallowSnapshots=false -DallowDowngrade=true
call mvn -B release:clean release:prepare -DcheckModificationExcludeList=pom.xml -DpreparationGoals=deploy
call git push
call mvn org.codehaus.mojo:versions-maven-plugin:update-properties -DallowSnapshots=true
call git add *
call git commit -m "Upgrading dependency versions"
call git push
call mvn deploy -DskipTests
cd scripts
