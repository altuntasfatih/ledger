# start dev
if [ "$1" = "dev" ]; then
  tigerbeetle start --addresses=3000 --development ./0_0.tigerbeetle
else
  rm ./0_0.tigerbeetle_test
  tigerbeetle format --cluster=0 --replica=0 --replica-count=1 --development ./0_0.tigerbeetle_test
  tigerbeetle start --addresses=3001 --development ./0_0.tigerbeetle_test
fi