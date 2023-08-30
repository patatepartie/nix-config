# App prefixes:
# Common: c
# Webchat: w
# Hachi: h
# Beair: a
# Believe: l
# Beship: s
# Beaware: w
# Db-tools: d
# Beetle: t
# Terraform-conf: f
# Infra: i

alias bc='beall-compose'
alias bcb='beall-compose build'
alias bccu='beall-compose up mysql redis duckling'
alias bcwu='beall-compose up --build webchat'
alias bchu='beall-compose up --build hachi hachi_threaded hachi_async sidekiq'
alias bchuh='beall-compose -a honeycomb up --build hachi hachi_threaded hachi_async sidekiq'
alias bcau='beall-compose up --build beair beair_sidekiq'
alias bcauh='beall-compose -a honeycomb up --build beair beair_sidekiq'
alias bclu='beall-compose up --build believe believe_celery_matching'
alias bcluh='beall-compose -a honeycomb up --build believe believe_celery_matching'
alias bcsu='beall-compose -s beship up --build beship'
alias bcs='beall-compose -s beship'
alias bcsd='beall-compose -s beship.dev'
alias bcst='beall-compose -s beship.test'
alias bcss='beall-compose -s beship.dev up --build beship-sync'
alias bcsr='beall-compose -s beship.dev run --rm beship bash'
alias bcsts='beall-compose -s beship.test run --rm beship bash'
alias bcsto='beall-compose -s beship.test stop chrome'
alias bcd='beall-compose -s db-tools'
alias bcdr='beall-compose -s db-tools run --rm db-tools'
alias bcdih='beall-compose -s db-tools run --rm db-tools import hachi'
alias bcdia='beall-compose -s db-tools run --rm db-tools import beair'
alias bcdis='beall-compose -s db-tools run --rm db-tools import beship'
