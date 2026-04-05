cd ..
call git reset --hard HEAD || exit /b 1
call git clean -fdx || exit /b 1
call git pull || exit /b 1
call mvn org.codehaus.mojo:versions-maven-plugin:update-properties -DallowSnapshots=false -DallowDowngrade=true || exit /b 1
call mvn org.farhan:sheep-dog-mgmt-maven-plugin:prepare -DpreparationGoals=deploy,-DskipTests || exit /b 1
call git push || exit /b 1
call git push --tags || exit /b 1
call mvn org.codehaus.mojo:versions-maven-plugin:update-properties -DallowSnapshots=true || exit /b 1
call git clean -fdx || exit /b 1
git diff --quiet HEAD -- . ":(exclude)*.bat" && (echo No dependency changes to commit) || (call git add * && call git commit -m "Upgrading dependency versions" && call git push)
call mvn clean deploy -DskipTests || exit /b 1
cd scripts
