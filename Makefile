.PHONY: watch run

run:
	lake exe desafio

watch:
	watchexec -e lean -r 'lake exe desafio'
