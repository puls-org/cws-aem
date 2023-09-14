deploy: bundle
	rm -rf function.zip ; zip -r function.zip *.rb vendor;
	aws --profile chanel lambda update-function-code --function-name aem-dictionary-ruby \
--zip-file fileb://function.zip

bundle:
	bundle install --path='./vendor/bundle'
run:
	@export $(cat .env | xargs) && ruby main.rb
