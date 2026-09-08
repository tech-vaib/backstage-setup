/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install nvm
mkdir -p ~/.nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix nvm)/nvm.sh" ] && \. "$(brew --prefix nvm)/nvm.sh"
source ~/.zshrc
nvm install 22
nvm use 22
nvm alias default 22
corepack enable
yarn set version 4.4.1
mkdir -p ~/workspace
cd ~/workspace
npx @backstage/create-app@latest
Enter a name for the app:
cd company-backstage
yarn start


cat .gitignore
node_modules/
dist-types/
dist/
coverage/
-----------------

sudo apt install -y \
  git \
  curl \
  build-essential \
  python3 \
  python3-pip \
  docker.io
  
  sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22
nvm alias default 22
cd ~
git clone <YOUR-GITHUB-REPO>
cd company-backstage
yarn install
yarn tsc
yarn start

docker image build \
  . \
  -f packages/backend/Dockerfile \
  -t company-backstage:latest
  
  docker run -d \
  --name backstage \
  -p 7007:7007 \
  company-backstage:latest
