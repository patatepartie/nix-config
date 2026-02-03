# App prefixes:
# Common: c
# Webchat: w
# Hachi: h
# Beair: a
# Believe: l
# Betrained: t
# Beproduced: p
# Beship: s
# Beaware: w
# Db-tools: d
# Beetle: t
# Terraform-conf: f
# Infra: i

alias bc='beall-compose'
alias bcb='beall-compose build'
alias bccu='beall-compose up mysql redis'
alias bcwu='beall-compose up --build webchat'
alias bchu='beall-compose up --build hachi hachi_threaded hachi_async sidekiq'
alias bchuh='beall-compose -a honeycomb up --build hachi hachi_threaded hachi_async sidekiq'
alias bcau='beall-compose up --build beair beair_sidekiq'
alias bcauh='beall-compose -a honeycomb up --build beair beair_sidekiq'
alias bclu='beall-compose up --build believe believe_celery_matching believe_celery_brag believe_celery_brag_admin'
alias bcluh='beall-compose -a honeycomb up --build believe believe_celery_matching believe_celery_brag believe_celery_brag_admin'
alias bctu='beall-compose -s betrained up --build betrained betrained_sidekiq'
alias bctuh='beall-compose -s betrained -a honeycomb up --build betrained betrained_sidekiq'
alias bcpu='beall-compose -s beproduced up --build beproduced_web beproduced_celery beproduced_celery_cpu'
alias bcpuh='beall-compose -s beproduced -a honeycomb up --build beproduced_web beproduced_celery beproduced_celery_cpu'
alias bcsu='beall-compose -s beship up --build beship'
alias bcs='beall-compose -s beship'
alias bcsd='beall-compose -s beship.dev'
alias bcst='beall-compose -s beship.test'
alias bcss='beall-compose -s beship.dev up --build beship-sync'
alias bcsr='beall-compose -s beship.dev run --rm --build beship bash'
alias bcsts='beall-compose -s beship.test run --rm --build beship bash'
alias bcsto='beall-compose -s beship.test stop chrome'
alias bcd='beall-compose -s db-tools'
alias bcdr='beall-compose -s db-tools run --rm --build db-tools'
alias bcdih='beall-compose -s db-tools run --rm --build db-tools import hachi'
alias bcdia='beall-compose -s db-tools run --rm --build db-tools import beair'
alias bcdis='beall-compose -s db-tools run --rm --build db-tools import beship'
alias bcdit='beall-compose -s db-tools run --rm --build db-tools import betrained'
